import Foundation
import MWConfig
import MWMeetings
import MWSupport
import MWVoices

/// Turn vectors per segment and provider key, and each key's evaluation against the people's
/// voices (design v8 R6–R8, R28).
///
/// `ingest` cuts a segment's audio at once, so a buffer that moves on afterwards loses nothing,
/// and queues the embedding. One consumer works the queue in order, off the caller's thread, so
/// a revision always finds the vectors of the segments it moves.
actor VoiceRecogniser {
    /// The controller's view of a key's speaker (R8).
    struct Context: Sendable, Equatable {
        /// The speaker is still `Speaker <id>`, unlinked and not the user.
        var evaluate: Bool
        /// People the user rejected for the speaker.
        var rejected: Set<UUID>
        /// The user's own entry is a candidate: in-room meetings.
        var includeUser: Bool
    }

    /// A sure or suggested match; "nothing" is never sent.
    struct Decision: Sendable, Equatable {
        enum Outcome: Sendable, Equatable { case suggestion, sure }

        var key: String
        var outcome: Outcome
        var person: Person
        var score: Double
        var runnerUp: Double
        /// The key's speech when it was decided.
        var seconds: Double
    }

    private struct Turn {
        let segment: UUID
        var key: String
        var parts: [(VoiceVector, seconds: Double)] = []
    }

    private enum Job: Sendable {
        case turn(segment: UUID, key: String, windows: [VoiceWindow.Window], context: Context)
        case revise([(segment: UUID, key: String)], contexts: [String: Context])
        case finish(CheckedContinuation<Void, Never>)
    }

    /// Single consumer; ends once `finish()` has worked off the queue.
    nonisolated let decisions: AsyncStream<Decision>
    private nonisolated let decided: AsyncStream<Decision>.Continuation
    private nonisolated let queue: AsyncStream<Job>.Continuation

    private let embedder: any VoiceEmbedding
    private let settings: @Sendable () async -> VoiceSettings
    private let people: @Sendable () async -> [Person]

    private var turns: [Turn] = []
    /// The latest context given for each key.
    private var contexts: [String: Context] = [:]
    private var warned = false

    /// `settings` and `people` are read at each evaluation, so a change applies to the next one.
    init(
        embedder: any VoiceEmbedding,
        settings: @escaping @Sendable () async -> VoiceSettings,
        people: @escaping @Sendable () async -> [Person]
    ) {
        self.embedder = embedder
        self.settings = settings
        self.people = people
        (decisions, decided) = AsyncStream.makeStream()
        let (jobs, queue) = AsyncStream<Job>.makeStream()
        self.queue = queue
        Task { [weak self] in
            for await job in jobs {
                guard let self else { return }
                await self.run(job)
            }
        }
    }

    deinit {
        queue.finish()
        decided.finish()
    }

    /// Queues the turn vectors of a final segment with a provider label for `key`. `audio` is
    /// read before this returns.
    nonisolated func ingest(_ segment: Segment, key: String, audio: VoiceAudioBuffer, context: Context) {
        guard segment.providerLabel != nil else { return }
        let windows = VoiceWindow.windows(spans: VoiceWindow.spans(of: segment.words)) {
            audio.samples(from: $0, to: $1)
        }
        guard !windows.isEmpty else { return }
        queue.yield(.turn(segment: segment.id, key: key, windows: windows, context: context))
    }

    /// Moves the segments' vectors to their new keys and evaluates every key that changed, with
    /// its context in `contexts` or else the latest one it was given.
    nonisolated func revise(_ moves: [(segment: UUID, key: String)], contexts: [String: Context]) {
        guard !moves.isEmpty else { return }
        queue.yield(.revise(moves, contexts: contexts))
    }

    /// Works off the queue, then ends `decisions`; anything queued later is ignored.
    func finish() async {
        await withCheckedContinuation { done in
            if case .terminated = queue.yield(.finish(done)) { done.resume() }
            queue.finish()
        }
    }

    /// Every key's normalised, seconds-weighted voice and its speech, for the sidecar.
    func voices() -> [String: (vector: VoiceVector, seconds: Double)] {
        Dictionary(grouping: turns, by: \.key).compactMapValues { owned in
            let parts = owned.flatMap(\.parts)
            return VoiceVector.combine(parts).map { ($0, Self.seconds(of: parts)) }
        }
    }

    private func run(_ job: Job) async {
        switch job {
        case .turn(let segment, let key, let windows, let context):
            contexts[key] = context
            guard let vectors = await embed(windows, key: key) else { return }
            turns.append(Turn(segment: segment, key: key))
            let index = turns.count - 1
            for (window, vector) in zip(windows, vectors) {
                turns[index].parts.append((vector, window.seconds))
                await evaluate(key)
            }
        case .revise(let moves, let given):
            contexts.merge(given) { $1 }
            var changed: [String] = []
            for move in moves {
                guard let index = turns.firstIndex(where: { $0.segment == move.segment }),
                      turns[index].key != move.key
                else { continue }
                changed += [turns[index].key, move.key]
                turns[index].key = move.key
            }
            var seen: Set<String> = []
            for key in changed where seen.insert(key).inserted {
                await evaluate(key)
            }
        case .finish(let done):
            decided.finish()
            done.resume()
        }
    }

    /// Nil when a window fails: the whole segment is skipped. Only the meeting's first failure is
    /// logged.
    private func embed(_ windows: [VoiceWindow.Window], key: String) async -> [VoiceVector]? {
        do {
            var vectors: [VoiceVector] = []
            for window in windows {
                vectors.append(try await embedder.embed(window.samples))
            }
            return vectors
        } catch {
            if !warned {
                warned = true
                Log.voice.warning("embedding failed for \(key), segment skipped: \(AnyError(error).description)")
            }
            return nil
        }
    }

    private func evaluate(_ key: String) async {
        guard key != MeetingVoices.userKey, let context = contexts[key], context.evaluate else { return }
        let parts = turns.filter { $0.key == key }.flatMap(\.parts)
        let seconds = Self.seconds(of: parts)
        let settings = await settings()
        guard seconds >= settings.minimumSpeechSeconds, let voice = VoiceVector.combine(parts) else { return }
        let match = VoiceMatcher.decide(
            probe: voice, people: await people(), settings: settings, excluding: context.rejected,
            includeUser: context.includeUser
        )
        guard match.outcome != .none, let person = match.person else { return }
        decided.yield(Decision(
            key: key, outcome: match.outcome == .sure ? .sure : .suggestion, person: person, score: match.score,
            runnerUp: match.runnerUp, seconds: seconds
        ))
    }

    private static func seconds(of parts: [(VoiceVector, seconds: Double)]) -> Double {
        parts.reduce(0) { $0 + $1.seconds }
    }
}
