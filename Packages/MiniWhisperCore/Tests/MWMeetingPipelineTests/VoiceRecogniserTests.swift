import Foundation
import MWConfig
import MWMeetings
import MWSupport
import MWTestSupport
import MWVoices
import Testing
import os

@testable import MWMeetingPipeline

@Suite(.timeLimit(.minutes(1))) struct VoiceRecogniserTests {
    // MARK: - Vectors

    @Test func aLabelledSegmentYieldsOneVectorPerWindow() async throws {
        let fake = FakeVoiceEmbedder()
        let rig = Rig(embedder: fake)

        rig.recogniser.ingest(turn(0, 12), key: "0:A", audio: buffer([(0.05, 30)]), context: .open)
        _ = await rig.finish()

        #expect(fake.windows.count == 2)
        #expect(fake.windows.allSatisfy { $0.count == VoiceWindow.windowSamples })
        let voice = try #require(await rig.recogniser.voices()["0:A"])
        #expect(voice.vector == .unit(5))
        #expect(isClose(voice.seconds, 12))
    }

    @Test func aSegmentWithoutALabelOrUnderOneAndAHalfSecondsYieldsNothing() async {
        let fake = FakeVoiceEmbedder()
        let rig = Rig(embedder: fake)
        let audio = buffer([(0.05, 30)])

        rig.recogniser.ingest(turn(0, 12, label: nil), key: "0:A", audio: audio, context: .open)
        rig.recogniser.ingest(turn(15, 16.4), key: "0:A", audio: audio, context: .open)
        rig.recogniser.ingest(turn(29, 40), key: "0:A", audio: audio, context: .open)
        _ = await rig.finish()

        #expect(fake.windows.isEmpty)
        #expect(await rig.recogniser.voices().isEmpty)
    }

    @Test func aKeysVoiceIsTheSecondsWeightedNormalisedSum() async throws {
        let rig = Rig()
        let audio = buffer([(0.05, 20), (0.07, 20)])

        rig.recogniser.ingest(turn(2, 6), key: "0:A", audio: audio, context: .open)
        rig.recogniser.ingest(turn(22, 24), key: "0:A", audio: audio, context: .open)
        _ = await rig.finish()

        let voice = try #require(await rig.recogniser.voices()["0:A"])
        let expected = try #require(VoiceVector.combine([(.unit(5), seconds: 4), (.unit(7), seconds: 2)]))
        #expect(voice.vector.cosine(expected) > 0.9999)
        #expect(isClose(Double(voice.vector.values[5]), 4 / 20.0.squareRoot()))
        #expect(isClose(Double(voice.vector.values[7]), 2 / 20.0.squareRoot()))
        #expect(isClose(voice.seconds, 6))
    }

    @Test func voicesSnapshotsEveryKeyForTheSidecar() async {
        let rig = Rig()
        let audio = buffer([(0.05, 20), (0.07, 20), (0.09, 20)])

        rig.recogniser.ingest(turn(0, 4), key: "0:A", audio: audio, context: .open)
        rig.recogniser.ingest(turn(20, 26), key: "0:B", audio: audio, context: .open)
        rig.recogniser.ingest(turn(40, 43), key: MeetingVoices.userKey, audio: audio, context: .closed)
        _ = await rig.finish()

        let voices = await rig.recogniser.voices()
        #expect(Set(voices.keys) == ["0:A", "0:B", MeetingVoices.userKey])
        #expect(voices["0:A"]?.vector == .unit(5))
        #expect(voices["0:B"]?.vector == .unit(7))
        #expect(voices[MeetingVoices.userKey]?.vector == .unit(9))
        #expect(isClose(voices["0:A"]?.seconds, 4))
        #expect(isClose(voices["0:B"]?.seconds, 6))
        #expect(isClose(voices[MeetingVoices.userKey]?.seconds, 3))
    }

    // MARK: - Evaluation

    @Test func evaluationWaitsForTheMinimumSpeech() async throws {
        let alice = person("Alice", sample: .unit(5))
        let rig = Rig(people: [alice])
        let audio = buffer([(0.05, 30)])

        rig.recogniser.ingest(turn(0, 14), key: "0:A", audio: audio, context: .open)
        rig.recogniser.ingest(turn(20, 22), key: "0:A", audio: audio, context: .open)
        let decisions = await rig.finish()

        let decision = try #require(decisions.first)
        #expect(decisions.count == 1)
        #expect(decision.person == alice)
        #expect(isClose(decision.seconds, 16))
    }

    @Test func settingsAndPeopleAreReadAtEachEvaluation() async {
        let alice = person("Alice", sample: near(5, cosine: 0.8))
        let rig = Rig(people: [alice])
        let audio = buffer([(0.05, 40)])
        var decisions = rig.recogniser.decisions.makeAsyncIterator()

        rig.recogniser.ingest(turn(0, 16), key: "0:A", audio: audio, context: .open)
        let first = await decisions.next()
        rig.settings.withLock { $0.sureThreshold = 0.9 }
        rig.recogniser.ingest(turn(20, 22), key: "0:A", audio: audio, context: .open)
        let second = await decisions.next()
        let bob = person("Bob", sample: .unit(5))
        rig.people.withLock { $0 = [bob] }
        rig.recogniser.ingest(turn(30, 32), key: "0:A", audio: audio, context: .open)
        let third = await decisions.next()

        #expect(first?.outcome == .sure)
        #expect(first?.person == alice)
        #expect(second?.outcome == .suggestion)
        #expect(second?.person == alice)
        #expect(third?.outcome == .sure)
        #expect(third?.person == bob)
    }

    @Test func aSureMatchIsDecidedSure() async throws {
        let alice = person("Alice", sample: near(5, cosine: 0.8))
        let bob = person("Bob", sample: near(5, cosine: 0.3))
        let rig = Rig(people: [alice, bob])

        rig.recogniser.ingest(turn(0, 16), key: "0:A", audio: buffer([(0.05, 20)]), context: .open)
        let decisions = await rig.finish()

        let decision = try #require(decisions.first)
        #expect(decisions.count == 1)
        #expect(decision.key == "0:A")
        #expect(decision.outcome == .sure)
        #expect(decision.person == alice)
        #expect(isClose(decision.score, 0.8))
        #expect(isClose(decision.runnerUp, 0.3))
        #expect(isClose(decision.seconds, 16))
    }

    @Test func aMiddlingMatchIsASuggestion() async throws {
        let alice = person("Alice", sample: near(5, cosine: 0.6))
        let rig = Rig(people: [alice])

        rig.recogniser.ingest(turn(0, 16), key: "0:A", audio: buffer([(0.05, 20)]), context: .open)
        let decisions = await rig.finish()

        let decision = try #require(decisions.first)
        #expect(decisions.count == 1)
        #expect(decision.outcome == .suggestion)
        #expect(decision.person == alice)
        #expect(isClose(decision.score, 0.6))
        #expect(decision.runnerUp == 0)
    }

    @Test func aWeakMatchDecidesNothing() async {
        let rig = Rig(people: [person("Alice", sample: near(5, cosine: 0.3))])

        rig.recogniser.ingest(turn(0, 16), key: "0:A", audio: buffer([(0.05, 20)]), context: .open)

        #expect(await rig.finish().isEmpty)
    }

    @Test func rejectedPeopleAreNotOffered() async throws {
        let alice = person("Alice", sample: .unit(5))
        let bob = person("Bob", sample: near(5, cosine: 0.8))
        let rig = Rig(people: [alice, bob])
        let context = VoiceRecogniser.Context(evaluate: true, rejected: [alice.id], includeUser: false)

        rig.recogniser.ingest(turn(0, 16), key: "0:A", audio: buffer([(0.05, 20)]), context: context)
        let decisions = await rig.finish()

        #expect(decisions.map(\.person) == [bob])
        #expect(decisions.map(\.outcome) == [.sure])
    }

    @Test func theUserIsOfferedOnlyWhenTheContextSaysSo() async {
        let user = person("Cagri", sample: .unit(5), isUser: true)
        let rig = Rig(people: [user])
        let audio = buffer([(0.05, 40)])
        let inTheRoom = VoiceRecogniser.Context(evaluate: true, rejected: [], includeUser: true)

        rig.recogniser.ingest(turn(0, 16), key: "0:A", audio: audio, context: .open)
        rig.recogniser.ingest(turn(20, 36), key: "0:B", audio: audio, context: inTheRoom)
        let decisions = await rig.finish()

        #expect(decisions.map(\.key) == ["0:B"])
        #expect(decisions.map(\.person) == [user])
    }

    @Test func aClosedContextIsNotEvaluated() async {
        let rig = Rig(people: [person("Alice", sample: .unit(5))])

        rig.recogniser.ingest(turn(0, 16), key: "0:A", audio: buffer([(0.05, 20)]), context: .closed)

        #expect(await rig.finish().isEmpty)
    }

    @Test func theUserKeyIsFedButNeverEvaluated() async {
        let fake = FakeVoiceEmbedder()
        let rig = Rig(
            people: [person("Cagri", sample: .unit(5), isUser: true), person("Alice", sample: .unit(5))],
            embedder: fake
        )
        let everyone = VoiceRecogniser.Context(evaluate: true, rejected: [], includeUser: true)

        rig.recogniser.ingest(turn(0, 16), key: MeetingVoices.userKey, audio: buffer([(0.05, 20)]), context: everyone)
        let decisions = await rig.finish()

        #expect(decisions.isEmpty)
        #expect(fake.windows.count == 2)
        #expect(isClose(await rig.recogniser.voices()[MeetingVoices.userKey]?.seconds, 16))
    }

    // MARK: - Revision

    @Test func aRevisionMovesVectorsAndReEvaluatesBothKeysWithoutEmbedding() async {
        let alice = person("Alice", sample: .unit(5))
        let bob = person("Bob", sample: .unit(7))
        let fake = FakeVoiceEmbedder()
        let rig = Rig(people: [alice, bob], embedder: fake)
        let audio = buffer([(0.05, 20), (0.07, 20)])
        let moved = turn(20, 36)

        rig.recogniser.ingest(turn(0, 16), key: "0:A", audio: audio, context: .closed)
        rig.recogniser.ingest(moved, key: "0:A", audio: audio, context: .closed)
        rig.recogniser.revise([(segment: moved.id, key: "0:B")], contexts: ["0:A": .open, "0:B": .open])
        let decisions = await rig.finish()

        #expect(fake.windows.count == 4)
        #expect(decisions.map(\.key) == ["0:A", "0:B"])
        #expect(decisions.map(\.person) == [alice, bob])
        #expect(decisions.map(\.outcome) == [.sure, .sure])
        let voices = await rig.recogniser.voices()
        #expect(voices["0:A"]?.vector == .unit(5))
        #expect(voices["0:B"]?.vector == .unit(7))
        #expect(isClose(voices["0:A"]?.seconds, 16))
        #expect(isClose(voices["0:B"]?.seconds, 16))
    }

    @Test func aRevisionWithoutAContextUsesTheKeysLatestOne() async {
        let alice = person("Alice", sample: .unit(5))
        let rig = Rig(people: [alice])
        let audio = buffer([(0.05, 40)])
        let moved = turn(20, 36)

        rig.recogniser.ingest(turn(0, 8), key: "0:B", audio: audio, context: .open)
        rig.recogniser.ingest(moved, key: "0:A", audio: audio, context: .closed)
        rig.recogniser.revise([(segment: moved.id, key: "0:B")], contexts: [:])
        let decisions = await rig.finish()

        #expect(decisions.map(\.key) == ["0:B"])
        #expect(decisions.map(\.person) == [alice])
        #expect(isClose(decisions.first?.seconds, 24))
    }

    // MARK: - Failures and the queue

    @Test func anEmbeddingErrorSkipsTheSegmentAndWarnsOncePerMeeting() async {
        let logs = CapturingLogSink()
        let embedder = PartlyFailingEmbedder(failing: .unit(9))
        let audio = buffer([(0.05, 20), (0.09, 20)])

        let voices = await Log.withSinks(debug: true, sinks: [logs]) {
            let rig = Rig(embedder: embedder)
            rig.recogniser.ingest(turn(10, 22), key: "0:A", audio: audio, context: .open)
            rig.recogniser.ingest(turn(25, 30), key: "0:A", audio: audio, context: .open)
            rig.recogniser.ingest(turn(0, 6), key: "0:B", audio: audio, context: .open)
            _ = await rig.finish()
            let voices = await rig.recogniser.voices()

            let next = Rig(embedder: embedder)
            next.recogniser.ingest(turn(25, 30), key: "0:A", audio: audio, context: .open)
            _ = await next.finish()
            return voices
        }

        #expect(Set(voices.keys) == ["0:B"])
        #expect(isClose(voices["0:B"]?.seconds, 6))
        let warnings = logs.records.filter { $0.level == .warning && $0.category == "voice" }
        #expect(warnings.count == 2)
        #expect(!logs.lines.contains { $0.contains("secret") })
    }

    @Test func audioIsCutAtIngestNotWhenTheQueueReachesIt() async {
        let gated = GatedEmbedder()
        let rig = Rig(embedder: gated)
        let audio = VoiceAudioBuffer(seconds: 20)
        audio.append([Float](repeating: 0.05, count: 20 * 16_000), at: 0)

        rig.recogniser.ingest(turn(0, 4), key: "0:A", audio: audio, context: .open)
        rig.recogniser.ingest(turn(5, 12), key: "0:B", audio: audio, context: .open)
        audio.append([Float](repeating: 0.09, count: 30 * 16_000), at: 20)
        gated.open()
        _ = await rig.finish()

        let voices = await rig.recogniser.voices()
        #expect(voices["0:B"]?.vector == .unit(5))
        #expect(isClose(voices["0:B"]?.seconds, 7))
    }

    @Test func finishDrainsTheQueue() async {
        let fake = FakeVoiceEmbedder()
        let rig = Rig(embedder: fake)
        let audio = buffer([(0.05, 70)])

        for index in 0..<5 {
            rig.recogniser.ingest(turn(Double(index) * 13, Double(index) * 13 + 12), key: "0:\(index)", audio: audio, context: .open)
        }
        await rig.recogniser.finish()

        #expect(fake.windows.count == 10)
        #expect(await rig.recogniser.voices().count == 5)
        var ended = true
        for await _ in rig.recogniser.decisions { ended = false }
        #expect(ended)
        rig.recogniser.ingest(turn(0, 12), key: "0:9", audio: audio, context: .open)
        await rig.recogniser.finish()
        #expect(fake.windows.count == 10)
    }

    @Test @MainActor func embeddingRunsOffTheMainThread() async {
        let onMain = OSAllocatedUnfairLock(initialState: [Bool]())
        let fake = FakeVoiceEmbedder { window in
            onMain.withLock { $0.append(Thread.isMainThread) }
            return FakeVoiceEmbedder.byAmplitude(window)
        }
        let rig = Rig(embedder: fake)

        rig.recogniser.ingest(turn(0, 12), key: "0:A", audio: buffer([(0.05, 20)]), context: .open)
        await rig.recogniser.finish()

        #expect(onMain.withLock { $0 } == [false, false])
    }
}

// MARK: - Helpers

extension VoiceRecogniser.Context {
    fileprivate static let open = Self(evaluate: true, rejected: [], includeUser: false)
    fileprivate static let closed = Self(evaluate: false, rejected: [], includeUser: false)
}

/// A recogniser whose settings and people the test can change between evaluations.
private struct Rig {
    let settings: OSAllocatedUnfairLock<VoiceSettings>
    let people: OSAllocatedUnfairLock<[Person]>
    let recogniser: VoiceRecogniser

    init(people: [Person] = [], embedder: any VoiceEmbedding = FakeVoiceEmbedder()) {
        let settings = OSAllocatedUnfairLock(initialState: VoiceSettings())
        let stored = OSAllocatedUnfairLock(initialState: people)
        self.settings = settings
        self.people = stored
        recogniser = VoiceRecogniser(
            embedder: embedder, settings: { settings.withLock { $0 } }, people: { stored.withLock { $0 } }
        )
    }

    /// Drains the queue; every decision made.
    func finish() async -> [VoiceRecogniser.Decision] {
        await recogniser.finish()
        var decisions: [VoiceRecogniser.Decision] = []
        for await decision in recogniser.decisions { decisions.append(decision) }
        return decisions
    }
}

/// Constant "voices" end to end from meeting second 0; `FakeVoiceEmbedder` hears amplitude 0.05
/// as `.unit(5)`.
private func buffer(_ voices: [(amplitude: Float, seconds: Int)]) -> VoiceAudioBuffer {
    let buffer = VoiceAudioBuffer(seconds: 120)
    var time = 0
    for voice in voices {
        buffer.append([Float](repeating: voice.amplitude, count: voice.seconds * 16_000), at: Double(time))
        time += voice.seconds
    }
    return buffer
}

/// A labelled turn whose padded speech is exactly `start..<end`.
private func turn(_ start: Double, _ end: Double, label: String? = "A") -> Segment {
    let first = start + VoiceWindow.padding, last = end - VoiceWindow.padding
    let words = stride(from: first, to: last, by: 1).map {
        Word(text: "secret", start: $0, end: min($0 + 1, last))
    }
    return Segment(
        speaker: 1, start: first, end: last, text: "the secret words", words: words, session: 0,
        providerLabel: label
    )
}

private func person(_ name: String, sample: VoiceVector, isUser: Bool = false) -> Person {
    Person(
        name: name, isUser: isUser, createdAt: .distantPast,
        local: [LocalSample(meeting: UUID(), at: .distantPast, seconds: 20, vector: sample)]
    )
}

/// A unit vector whose cosine with `.unit(axis)` is `cosine`.
private func near(_ axis: Int, cosine: Float) -> VoiceVector {
    var values = [Float](repeating: 0, count: VoiceVector.dimension)
    values[axis] = cosine
    values[VoiceVector.dimension - 1] = (1 - cosine * cosine).squareRoot()
    return VoiceVector(values)
}

/// Embeds as `FakeVoiceEmbedder` does, but throws for every window of `failing`'s voice.
private struct PartlyFailingEmbedder: VoiceEmbedding {
    let failing: VoiceVector

    func prepare() async throws {}

    func embed(_ window: [Float]) async throws -> VoiceVector {
        let vector = FakeVoiceEmbedder.byAmplitude(window)
        guard vector != failing else { throw VoiceEmbeddingError.badWindow }
        return vector
    }
}

/// Holds every `embed` until `open()`, so the queue stands still while the test moves the buffer on.
private final class GatedEmbedder: VoiceEmbedding, @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func open() {
        let resumed = lock.withLock {
            isOpen = true
            defer { waiting = [] }
            return waiting
        }
        resumed.forEach { $0.resume() }
    }

    func prepare() async throws {}

    func embed(_ window: [Float]) async throws -> VoiceVector {
        await withCheckedContinuation { continuation in
            let passes = lock.withLock {
                if !isOpen { waiting.append(continuation) }
                return isOpen
            }
            if passes { continuation.resume() }
        }
        return FakeVoiceEmbedder.byAmplitude(window)
    }
}
