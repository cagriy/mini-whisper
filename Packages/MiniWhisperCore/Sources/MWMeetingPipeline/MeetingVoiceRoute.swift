import Foundation
import MWConfig
import MWMeetings
import MWSupport
import MWVoices

/// The voice-recognition side of one meeting (design v8 §5 Control flow): its buffers, recogniser
/// and per-key voices. The controller keeps the registry, persistence and events, and calls in at
/// Start, on each segment and revision, and at Stop.
@MainActor
final class MeetingVoiceRoute {
    /// The bundled model, named in the local sidecar.
    static let localModel = "wespeaker_v2"

    /// A person for a provider key, sure or suggested.
    struct Match: Sendable {
        var key: String
        var sure: Bool
        var person: Person
        /// Nil on the Speechmatics route, which gives no score.
        var score: Double?
        var runnerUp: Double?
        /// The key's speech when it was decided.
        var seconds: Double?
    }

    let route: VoiceRoute
    private let deps: VoiceDependencies
    private let meeting: UUID
    private let mode: MeetingMode
    /// What the capture tick fills.
    let buffers: VoiceBuffers?
    private let recogniser: VoiceRecogniser?
    private var preparing: Task<Void, Never>?
    private var consuming: Task<Void, Never>?
    /// False for good once the model failed to load.
    private(set) var isActive = true
    /// The switch as the ticker last read it; segments are not fed while it is off.
    private var isOn = true

    /// The route of a meeting about to start, or nil when R2 leaves it inactive: no voice
    /// dependencies, a test call, the engine's switch off, or not an engine of the local route.
    static func live(
        _ deps: VoiceDependencies?, engine: MeetingEngine, mode: MeetingMode, meeting: UUID, isTest: Bool,
        settings: VoiceSettings, current: @escaping @Sendable () async -> VoiceSettings
    ) -> MeetingVoiceRoute? {
        guard let deps, !isTest, settings.isEnabled(engine.voiceRoute), engine.voiceRoute == .local else { return nil }
        return MeetingVoiceRoute(local: deps, meeting: meeting, mode: mode, settings: settings, current: current)
    }

    private init(
        local deps: VoiceDependencies, meeting: UUID, mode: MeetingMode, settings: VoiceSettings,
        current: @escaping @Sendable () async -> VoiceSettings
    ) {
        route = .local
        self.deps = deps
        self.meeting = meeting
        self.mode = mode
        buffers = VoiceBuffers(
            microphone: VoiceAudioBuffer(seconds: settings.bufferSeconds),
            system: mode == .remote ? VoiceAudioBuffer(seconds: settings.bufferSeconds) : nil
        )
        recogniser = VoiceRecogniser(embedder: deps.embedder, settings: current) { [store = deps.store] in
            await store.people()
        }
    }

    /// R8, R16: a speaker recognition may still name: `Speaker <id>`, unlinked, not the user.
    static func isOpen(_ label: SpeakerLabel) -> Bool {
        !label.isUser && label.person == nil && label.name == SpeakerRegistry.defaultName(label.id)
    }

    static func speaker(owning key: String, in labels: [SpeakerLabel]) -> SpeakerLabel? {
        labels.first { $0.providerKeys.contains(key) }
    }

    // MARK: - Live

    /// Loads the model without holding up Start and hands every decision to `matched`. `failed`
    /// runs if the model cannot load; the route is off for the meeting from then on.
    func begin(
        matched: @escaping @MainActor @Sendable (Match) async -> Void,
        failed: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let recogniser else { return }
        preparing = Task { [weak self, embedder = deps.embedder] in
            let started = ContinuousClock.now
            do {
                try await embedder.prepare()
                let seconds = (ContinuousClock.now - started) / .seconds(1)
                Log.voice.info("model loaded in \(String(format: "%.2f", seconds)) s")
            } catch {
                Log.voice.warning("model not loaded: \(AnyError(error).description)")
                self?.isActive = false
                failed()
            }
        }
        consuming = Task { [decisions = recogniser.decisions] in
            for await decision in decisions {
                await matched(Match(
                    key: decision.key, sure: decision.outcome == .sure, person: decision.person,
                    score: decision.score, runnerUp: decision.runnerUp, seconds: decision.seconds
                ))
            }
        }
    }

    func refresh(_ settings: VoiceSettings) {
        isOn = settings.isEnabled(route)
    }

    /// Feeds each labelled segment to the recogniser under its key, with its speaker's state.
    func heard(_ segments: [Segment], speakers: [SpeakerLabel]) {
        guard let recogniser, let buffers, isActive, isOn else { return }
        for segment in segments where segment.providerLabel != nil {
            let key = key(of: segment)
            let audio = (mode == .remote && key != MeetingVoices.userKey ? buffers.system : nil) ?? buffers.microphone
            recogniser.ingest(segment, key: key, audio: audio, context: context(of: key, speakers))
        }
    }

    /// A revision re-labelled these segments: their vectors follow them to their new keys.
    func revised(_ changes: [(before: Segment, after: Segment)], speakers: [SpeakerLabel]) {
        guard let recogniser, isActive else { return }
        var contexts: [String: VoiceRecogniser.Context] = [:]
        let moves = changes.map { change in
            let to = key(of: change.after)
            for changed in [key(of: change.before), to] { contexts[changed] = context(of: changed, speakers) }
            return (segment: change.after.id, key: to)
        }
        recogniser.revise(moves, contexts: contexts)
    }

    /// Stop: lets the model finish loading and works off the queue and every decision, then
    /// returns each key's voice as the sidecar holds it.
    func finish() async -> MeetingVoices {
        await preparing?.value
        var sidecar = MeetingVoices(route: route, model: Self.localModel)
        guard let recogniser else { return sidecar }
        await recogniser.finish()
        await consuming?.value
        sidecar.keys = await recogniser.voices().mapValues { .init(seconds: $0.seconds, vector: $0.vector) }
        return sidecar
    }

    // MARK: - Match log

    /// R23, R27: the match log's line, and a `Log.voice` line of keys, scores and seconds.
    func logMatch(_ match: Match, at date: Date) async {
        let score = match.score.map { String(format: " %.2f (next %.2f)", $0, match.runnerUp ?? 0) } ?? ""
        let seconds = match.seconds.map { " after \(Int($0.rounded())) s" } ?? ""
        Log.voice.info(
            "match \(match.key) \(match.sure ? "sure" : "suggestion")\(score)\(seconds), person \(Self.short(match.person.id))"
        )
        await append(MatchLog.Entry(
            at: date, meeting: meeting, key: match.key, route: route, event: match.sure ? .applied : .suggested,
            person: match.person.id, score: match.score, runnerUp: match.runnerUp, seconds: match.seconds
        ))
    }

    private func append(_ entry: MatchLog.Entry) async {
        do {
            try await deps.log.append(entry)
        } catch {
            Log.voice.warning("match log not written: \(AnyError(error).description)")
        }
    }

    /// The first 8 characters of a person id, all a log line may carry.
    static func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).lowercased()
    }

    // MARK: - Keys

    /// A remote meeting's user speaks into the microphone: all their segments are one key.
    private func key(of segment: Segment) -> String {
        mode == .remote && segment.speaker == SpeakerRegistry.userID
            ? MeetingVoices.userKey
            : SpeakerRegistry.key(session: segment.session, label: segment.providerLabel)
    }

    private func context(of key: String, _ speakers: [SpeakerLabel]) -> VoiceRecogniser.Context {
        let owner = Self.speaker(owning: key, in: speakers)
        return VoiceRecogniser.Context(
            evaluate: owner.map(Self.isOpen) ?? false, rejected: Set(owner?.rejected ?? []),
            includeUser: mode == .inRoom
        )
    }
}
