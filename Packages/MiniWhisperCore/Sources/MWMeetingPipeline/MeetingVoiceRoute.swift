import Foundation
import MWConfig
import MWMeetings
import MWSupport
import MWVoices

/// The voice-recognition side of one meeting (design v8 §5 Control flow): its buffers, recogniser
/// and per-key voices, and what a link teaches the people store. The controller keeps the
/// registry, persistence and events, and calls in at Start, on each segment, revision and link,
/// and at Stop. A stored meeting's route holds only its sidecar.
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
    private let now: @Sendable () -> Date
    /// What the capture tick fills.
    let buffers: VoiceBuffers?
    private let recogniser: VoiceRecogniser?
    /// The sidecar's voices, once the meeting has stopped or was opened.
    private var stored: MeetingVoices?
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
        settings: VoiceSettings, now: @escaping @Sendable () -> Date,
        current: @escaping @Sendable () async -> VoiceSettings
    ) -> MeetingVoiceRoute? {
        guard let deps, !isTest, settings.isEnabled(engine.voiceRoute), engine.voiceRoute == .local else { return nil }
        return MeetingVoiceRoute(
            local: deps, meeting: meeting, mode: mode, settings: settings, now: now, current: current
        )
    }

    private init(
        local deps: VoiceDependencies, meeting: UUID, mode: MeetingMode, settings: VoiceSettings,
        now: @escaping @Sendable () -> Date, current: @escaping @Sendable () async -> VoiceSettings
    ) {
        route = .local
        self.deps = deps
        self.meeting = meeting
        self.mode = mode
        self.now = now
        buffers = VoiceBuffers(
            microphone: VoiceAudioBuffer(seconds: settings.bufferSeconds),
            system: mode == .remote ? VoiceAudioBuffer(seconds: settings.bufferSeconds) : nil
        )
        recogniser = VoiceRecogniser(embedder: deps.embedder, settings: current) { [store = deps.store] in
            await store.people()
        }
    }

    /// A stored meeting's route: links made on it learn from its sidecar (R22).
    init(
        stored deps: VoiceDependencies, sidecar: MeetingVoices, meeting: UUID, mode: MeetingMode,
        now: @escaping @Sendable () -> Date
    ) {
        route = sidecar.route
        self.deps = deps
        self.meeting = meeting
        self.mode = mode
        self.now = now
        buffers = nil
        recogniser = nil
        stored = sidecar
    }

    /// The sidecar's keys.
    var keys: Set<String> { stored.map { Set($0.keys.keys) } ?? [] }

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
    /// keeps each key's voice as the sidecar holds it, for links made after Stop.
    func finish() async -> MeetingVoices {
        await preparing?.value
        await recogniser?.finish()
        await consuming?.value
        let sidecar = MeetingVoices(route: route, model: Self.localModel, keys: await voices())
        stored = sidecar
        return sidecar
    }

    /// Each key's voice data: the sidecar's once the meeting has stopped, else the recogniser's.
    private func voices() async -> [String: MeetingVoices.Entry] {
        if let stored { return stored.keys }
        return await recogniser?.voices().mapValues { .init(seconds: $0.seconds, vector: $0.vector) } ?? [:]
    }

    // MARK: - Learning

    /// R18, R19: the person a speaker's name means: the user's own entry, named after the
    /// meeting's user name, for the user; the People entry of that name, or a new one, otherwise.
    /// Nil for a default `Speaker N` name, which never names a person (R17).
    func person(for label: SpeakerLabel, userName: String) async -> Person? {
        guard label.name.wholeMatch(of: /Speaker \d+/) == nil else { return nil }
        guard !label.isUser else { return await user(named: userName) }
        let (name, at) = (label.name, now())
        return await updatePeople { try await $0.findOrCreate(named: name, at: at) } ?? nil
    }

    func user(named name: String) async -> Person? {
        let at = now()
        return await updatePeople { try await $0.user(named: name, at: at) }
    }

    /// Design v8 §5 Stop (R19): the user's speaker has a voice of its own: on the local route in a
    /// remote meeting the microphone's `minimum` seconds of speech, otherwise a key it owns.
    func hasUserVoice(_ labels: [SpeakerLabel], minimum: Double) async -> Bool {
        guard let user = labels.first(where: \.isUser) else { return false }
        let voices = await voices()
        guard route == .local, mode == .remote else { return user.providerKeys.contains { voices[$0] != nil } }
        return (voices[MeetingVoices.userKey]?.seconds ?? 0) >= minimum
    }

    /// Design v8 §5 Link (R17, R20): this meeting's sample of each person whose linked keys differ
    /// between `before` and `after`, or of everyone linked in either with `everyone`, is recomputed
    /// from the keys linked to them now; a person left without a voice here loses its sample.
    func relearn(from before: [SpeakerLabel], to after: [SpeakerLabel], everyone: Bool = false) async {
        let was = keysByPerson(before), linked = keysByPerson(after)
        let changed = Set(was.keys).union(linked.keys).filter { everyone || was[$0] != linked[$0] }
        guard !changed.isEmpty else { return }
        let voices = await voices()
        for person in changed { await learn(person, from: linked[person] ?? [], voices) }
    }

    /// `lastHeard` for the people linked or applied in the meeting.
    func markHeard(_ labels: [SpeakerLabel]) async {
        let applied = labels.flatMap(\.matches).filter { $0.state == .applied }.compactMap(\.person)
        let heard = Set(labels.compactMap(\.person) + applied)
        guard !heard.isEmpty else { return }
        let at = now()
        await updatePeople { try await $0.markHeard(heard, at: at) }
    }

    private func learn(_ person: UUID, from keys: Set<String>, _ voices: [String: MeetingVoices.Entry]) async {
        switch route {
        case .local:
            let parts = keys.compactMap { voices[$0] }.compactMap { entry in
                entry.vector.map { ($0, seconds: entry.seconds) }
            }
            if let vector = VoiceVector.combine(parts) {
                let seconds = parts.reduce(0) { $0 + $1.seconds }
                let sample = LocalSample(meeting: meeting, at: now(), seconds: seconds, vector: vector)
                await updatePeople { try await $0.addLocalSample(sample, to: person) }
            } else {
                let meeting = meeting
                await updatePeople { try await $0.removeLocalSample(meeting: meeting, from: person) }
            }
        case .speechmatics:
            return
        }
    }

    /// The people linked to the meeting's speakers and the keys whose voice is theirs.
    private func keysByPerson(_ labels: [SpeakerLabel]) -> [UUID: Set<String>] {
        var keys: [UUID: Set<String>] = [:]
        for label in labels {
            guard let person = label.person else { continue }
            keys[person, default: []].formUnion(voiceKeys(of: label))
        }
        return keys
    }

    /// On the local route a remote meeting's user is the microphone's one key.
    private func voiceKeys(of label: SpeakerLabel) -> [String] {
        route == .local && mode == .remote && label.isUser ? [MeetingVoices.userKey] : label.providerKeys
    }

    /// A people-store change; a failed write is logged and the change kept for the next one.
    @discardableResult
    private func updatePeople<T: Sendable>(_ change: @Sendable (VoiceStore) async throws -> T) async -> T? {
        do {
            return try await change(deps.store)
        } catch {
            Log.voice.warning("voices.json not written: \(AnyError(error).description)")
            return nil
        }
    }

    // MARK: - Match log

    /// R23: a user's action on a match.
    func logAction(_ event: MatchLog.Event, key: String, person: UUID?) async {
        Log.voice.info("\(event.rawValue) \(key)\(person.map { ", person \(Self.short($0))" } ?? "")")
        await append(MatchLog.Entry(at: now(), meeting: meeting, key: key, route: route, event: event, person: person))
    }

    /// R23, R27: the match log's line, and a `Log.voice` line of keys, scores and seconds.
    func logMatch(_ match: Match) async {
        let score = match.score.map { String(format: " %.2f (next %.2f)", $0, match.runnerUp ?? 0) } ?? ""
        let seconds = match.seconds.map { " after \(Int($0.rounded())) s" } ?? ""
        let outcome = match.sure ? "sure" : "suggestion"
        Log.voice.info("match \(match.key) \(outcome)\(score)\(seconds), person \(Self.short(match.person.id))")
        await append(MatchLog.Entry(
            at: now(), meeting: meeting, key: match.key, route: route, event: match.sure ? .applied : .suggested,
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
