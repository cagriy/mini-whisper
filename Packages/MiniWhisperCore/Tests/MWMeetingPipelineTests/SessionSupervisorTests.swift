import AVFAudio
import Foundation
import Testing

import MWConfig
import MWCorrections
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWSupport
import MWTestSupport

private let key = "placeholder-not-a-real-key"
private let wallStart = Date(timeIntervalSince1970: 1_794_000_000)
private let lost = WebSocketConnectionError.closed(code: 4005, reason: nil)

private func buffer() -> AVAudioPCMBuffer {
    PCMBufferFactory.make(samples: [Float](repeating: 0, count: 320), sampleRate: 16_000)
}

private func segment(_ text: String, _ start: Double, _ end: Double) -> TranscriptSegment {
    TranscriptSegment(text: text, speaker: "A", start: start, end: end)
}

@Suite struct SessionSupervisorTests {
    @Test func openStartsOneSessionAndFeedsIt() async throws {
        let hints = RecognitionHints(terms: ["Northwind"], rules: [], vocabulary: [])
        var rig = Rig(engine: .speechmaticsEnhanced, hints: hints)
        rig.supervisor.open(at: 0)

        let calls = rig.provider.fakes.calls
        #expect(calls.map(\.engine) == [.speechmaticsEnhanced])
        #expect(calls.map(\.key) == [key])
        #expect(calls.map(\.hints) == [hints])
        for index in 0..<3 { rig.supervisor.feed(buffer(), at: Double(index) * 0.02) }
        #expect(rig.engines.map(\.fedBuffers) == [3])

        rig.supervisor.open(at: 1)
        #expect(rig.engines.count == 1)

        try rig.sink(1).onPartial("hello")
        #expect(await rig.next(2) == [.connection(.connected), .partial("hello")])
    }

    @Test func engineErrorReconnectsWithTheBackoffSequence() async throws {
        let rig = Rig()
        rig.supervisor.open(at: 0)

        var failures: [Double] = []
        for (index, delay) in [1.0, 2, 4, 8, 15, 30, 30].enumerated() {
            try rig.sink(index + 1).onEngineError(lost)
            failures.append(rig.clock.now)
            await rig.reopen(after: delay, session: index + 2)
        }

        #expect(rig.clock.sleeps == [1, 2, 4, 8, 15, 30, 30].map { Duration.seconds($0) })
        let reopens = zip(rig.provider.startTimes.dropFirst(), failures).map { $0 - $1 }
        #expect(reopens == [1, 2, 4, 8, 15, 30, 30])
    }

    enum Delivery: CaseIterable, Sendable {
        case partial, segment, sessionLimit
    }

    @Test(arguments: Delivery.allCases)
    func backoffResetsOnceTheNewSessionDelivers(_ delivery: Delivery) async throws {
        var rig = Rig()
        rig.supervisor.open(at: 0)
        try rig.sink(1).onEngineError(lost)
        await rig.reopen(after: 1, session: 2)
        try rig.sink(2).onEngineError(lost)
        await rig.reopen(after: 2, session: 3)

        let third = try rig.sink(3)
        switch delivery {
        case .partial: third.onPartial("back")
        case .segment: third.onSegment(segment("back", 0, 1))
        case .sessionLimit: third.onSessionLimit(.expiresAt(wallStart.addingTimeInterval(3 * 3600)))
        }
        third.onEngineError(lost)

        #expect(await rig.connectionStates(4) == [
            .reconnecting(attempt: 1), .reconnecting(attempt: 2), .connected, .reconnecting(attempt: 1),
        ])
        await rig.reopen(after: 1, session: 4)
        #expect(rig.clock.sleeps.last == .seconds(1))
    }

    @Test func reconnectingEventCarriesTheAttempt() async throws {
        var rig = Rig()
        rig.supervisor.open(at: 0)

        try rig.sink(1).onEngineError(lost)
        #expect(await rig.next(1) == [.connection(.reconnecting(attempt: 1))])
        await rig.reopen(after: 1, session: 2)

        try rig.sink(2).onEngineError(WebSocketConnectionError.closed(code: 1011, reason: "internal"))
        #expect(await rig.next(1) == [.connection(.reconnecting(attempt: 2))])
        await rig.reopen(after: 2, session: 3)

        try rig.sink(3).onEngineError(URLError(.networkConnectionLost))
        #expect(await rig.next(1) == [.connection(.reconnecting(attempt: 3))])
    }

    @Test func firstSegmentAfterAReconnectEmitsAGapMarker() async throws {
        var rig = Rig()
        rig.supervisor.open(at: 0)
        rig.supervisor.feed(buffer(), at: 0)
        let before = segment("before", 1, 4)
        try rig.sink(1).onSegment(before)
        try rig.sink(1).onEngineError(lost)

        await rig.reopen(after: 1, session: 2)
        rig.supervisor.feed(buffer(), at: 12)
        let after = segment("after", 0.5, 2)
        let next = segment("next", 2.5, 3)
        try rig.sink(2).onSegment(after)
        try rig.sink(2).onSegment(next)

        #expect(await rig.next(7) == [
            .connection(.connected),
            .segment(before, session: 1, origin: 0),
            .connection(.reconnecting(attempt: 1)),
            .connection(.connected),
            .gap(Marker(kind: .gap, start: 4, end: 12.5, reason: "connection lost")),
            .segment(after, session: 2, origin: 12),
            .segment(next, session: 2, origin: 12),
        ])
    }

    @Test func rolloverOpensTheNextSessionAtExpiresAtMinusSixty() async throws {
        var rig = Rig()
        rig.supervisor.open(at: 0)
        rig.supervisor.feed(buffer(), at: 0)
        rig.clock.base.advance(by: 100)

        try rig.sink(1).onSessionLimit(.expiresAt(wallStart.addingTimeInterval(3 * 3600)))
        #expect(await rig.next(1) == [.connection(.connected)])
        await rig.clock.base.waitUntilSleeping()
        #expect(rig.clock.sleeps.map(\.seconds) == [10_640])

        rig.clock.base.advance(by: 10_640)
        await rig.provider.started.wait(for: 2)
        #expect(rig.provider.startTimes == [0, 10_740])
        #expect(await rig.next(1) == [.connection(.rolledOver)])

        await rig.provider.finished.wait(for: 1)
        #expect(rig.engines.map(\.finishTimeout) == [.seconds(5), nil])
        rig.supervisor.feed(buffer(), at: 10_740)
        #expect(rig.engines.map(\.fedBuffers) == [1, 1])
    }

    @Test func expiryWithinSixtySecondsRollsOverAtOnce() async throws {
        var rig = Rig()
        rig.supervisor.open(at: 0)

        try rig.sink(1).onSessionLimit(.expiresAt(wallStart.addingTimeInterval(45)))
        try #require(rig.engines.count == 2)
        #expect(await rig.next(2) == [.connection(.connected), .connection(.rolledOver)])
        #expect(rig.clock.sleeps.isEmpty)
    }

    @Test func rolloverAfterASuccessfulOverlapEmitsNoGap() async throws {
        var rig = Rig()
        rig.supervisor.open(at: 0)
        rig.supervisor.feed(buffer(), at: 0)
        try rig.sink(1).onSessionLimit(.expiresAt(wallStart.addingTimeInterval(120)))
        await rig.clock.base.waitUntilSleeping()
        rig.clock.base.advance(by: 60)
        await rig.provider.started.wait(for: 2)

        rig.supervisor.feed(buffer(), at: 60)
        let drained = segment("drained", 50, 58)
        let fresh = segment("fresh", 0.5, 2)
        try rig.sink(1).onSegment(drained)
        try rig.sink(2).onSegment(fresh)

        #expect(await rig.next(5) == [
            .connection(.connected),
            .connection(.rolledOver),
            .segment(drained, session: 1, origin: 0),
            .connection(.connected),
            .segment(fresh, session: 2, origin: 60),
        ])
    }

    @Test func speechmaticsWarningRollsOverAtOnce() async throws {
        var rig = Rig(engine: .speechmaticsStandard)
        rig.supervisor.open(at: 0)

        try rig.sink(1).onSessionLimit(.warning)
        #expect(rig.engines.count == 2)
        _ = try rig.sink(2)
        #expect(await rig.next(2) == [.connection(.connected), .connection(.rolledOver)])
        await rig.provider.finished.wait(for: 1)
        #expect(rig.engines.map(\.finishTimeout) == [.seconds(5), nil])

        // The retired session's later warnings change nothing.
        try rig.sink(1).onSessionLimit(.warning)
        #expect(rig.engines.count == 2)
        #expect(rig.clock.sleeps.isEmpty)
    }

    @Test func oldSessionSegmentsStillDrainWithTheirSessionIndex() async throws {
        var rig = Rig()
        rig.supervisor.open(at: 0)
        rig.supervisor.feed(buffer(), at: 0)
        try rig.sink(1).onSessionLimit(.warning)
        rig.supervisor.feed(buffer(), at: 30)

        let old = segment("old", 20, 25)
        let new = segment("new", 1, 2)
        let revision = [SpeakerRevision(turnOrder: 3, speaker: "B")]
        try rig.sink(1).onPartial("stale")
        try rig.sink(1).onSegment(old)
        try rig.sink(1).onSpeakerRevision(revision)
        try rig.sink(2).onSegment(new)

        #expect(await rig.next(6) == [
            .connection(.connected),
            .connection(.rolledOver),
            .segment(old, session: 1, origin: 0),
            .revision(revision, session: 1),
            .connection(.connected),
            .segment(new, session: 2, origin: 30),
        ])
    }

    @Test func audioFedWhileClosedIsDropped() async throws {
        let rig = Rig()
        rig.supervisor.feed(buffer(), at: 0)
        #expect(rig.engines.isEmpty)

        rig.supervisor.open(at: 0.02)
        rig.supervisor.feed(buffer(), at: 0.02)
        try rig.sink(1).onEngineError(lost)
        rig.supervisor.feed(buffer(), at: 0.04)
        await rig.reopen(after: 1, session: 2)
        rig.supervisor.feed(buffer(), at: 1.04)
        await rig.supervisor.close()
        rig.supervisor.feed(buffer(), at: 1.06)

        #expect(rig.engines.map(\.fedBuffers) == [1, 1])
    }

    @Test func sessionAudioOriginIsTheMeetingTimeOfTheFirstFedBuffer() async throws {
        var rig = Rig()
        rig.supervisor.open(at: 0)
        rig.supervisor.feed(buffer(), at: 0.25)
        rig.supervisor.feed(buffer(), at: 0.27)
        let first = segment("first", 0, 1)
        try rig.sink(1).onSegment(first)
        try rig.sink(1).onEngineError(lost)
        rig.supervisor.feed(buffer(), at: 3)

        await rig.reopen(after: 1, session: 2)
        rig.supervisor.feed(buffer(), at: 7.5)
        rig.supervisor.feed(buffer(), at: 7.52)
        let second = segment("second", 0, 1)
        try rig.sink(2).onSegment(second)

        // A pause and resume: a fresh session, and no gap.
        await rig.supervisor.close()
        rig.supervisor.open(at: 100)
        rig.supervisor.feed(buffer(), at: 100.5)
        let third = segment("third", 0, 1)
        try rig.sink(3).onSegment(third)

        #expect(await rig.next(8) == [
            .connection(.connected),
            .segment(first, session: 1, origin: 0.25),
            .connection(.reconnecting(attempt: 1)),
            .connection(.connected),
            .gap(Marker(kind: .gap, start: 1.25, end: 7.5, reason: "connection lost")),
            .segment(second, session: 2, origin: 7.5),
            .connection(.connected),
            .segment(third, session: 3, origin: 100.5),
        ])
    }

    @Test func closeFinishesWithFiveSecondsAndStopsReconnecting() async throws {
        var rig = Rig()
        rig.supervisor.open(at: 0)
        rig.supervisor.feed(buffer(), at: 0)
        await rig.supervisor.close()
        #expect(rig.engines.map(\.finishTimeout) == [.seconds(5)])

        // Finals the closed session drains still arrive; its late failure reopens nothing.
        let late = segment("late", 1, 2)
        try rig.sink(1).onEngineError(lost)
        try rig.sink(1).onSegment(late)
        #expect(await rig.next(1) == [.segment(late, session: 1, origin: 0)])

        // Closing during a backoff cancels the pending reopen.
        rig.supervisor.open(at: 10)
        try rig.sink(2).onEngineError(lost)
        #expect(await rig.next(1) == [.connection(.reconnecting(attempt: 1))])
        await rig.clock.base.waitUntilSleeping()
        await rig.supervisor.close()
        rig.clock.base.advance(by: 60)
        #expect(rig.engines.count == 2)
    }

    @Test func closeCodeAndAttemptAreLogged() async throws {
        let logs = CapturingLogSink()
        let rig = Rig()
        try await Log.withSinks(debug: true, sinks: [logs]) {
            rig.supervisor.open(at: 0)
            try rig.sink(1).onPartial("the confidential transcript")
            try rig.sink(1).onEngineError(lost)
            await rig.reopen(after: 1, session: 2)
            try rig.sink(2).onEngineError(lost)
            await rig.reopen(after: 2, session: 3)
            try rig.sink(3).onEngineError(lost)
            await rig.reopen(after: 4, session: 4)
            try rig.sink(4).onSessionLimit(.warning)
            await rig.supervisor.close()
        }

        let lines = logs.lines
        #expect(lines.contains { $0.contains("4005") })
        #expect(lines.contains { $0.contains("attempt 3") })
        #expect(lines.contains { $0.contains("rolled over") })
        #expect(!lines.contains { $0.contains(key) || $0.contains("confidential") })
    }
}

// MARK: - Rig

private struct Rig {
    let clock: RecordingClock
    let provider: AnnouncingProvider
    let supervisor: SessionSupervisor
    private var iterator: AsyncStream<SupervisorEvent>.AsyncIterator

    init(engine: MeetingEngine = .assemblyaiStreaming, hints: RecognitionHints = .none) {
        let clock = RecordingClock()
        self.clock = clock
        provider = AnnouncingProvider(clock: clock.base)
        supervisor = SessionSupervisor(
            provider: provider, engine: engine, key: key, hints: hints, clock: clock,
            now: { wallStart.addingTimeInterval(clock.now) }
        )
        iterator = supervisor.events.makeAsyncIterator()
    }

    var engines: [FakeStreamingEngine] { provider.fakes.engines }

    /// The sink the supervisor started session `index` (from 1) with.
    func sink(_ index: Int) throws -> any TranscriptSink {
        let engines = engines
        try #require(engines.count >= index)
        return try #require(engines[index - 1].sink)
    }

    /// Lets a pending backoff of `seconds` elapse and waits for the reopened session.
    func reopen(after seconds: Double, session: Int) async {
        await clock.base.waitUntilSleeping()
        clock.base.advance(by: seconds)
        await provider.started.wait(for: session)
    }

    mutating func next(_ count: Int) async -> [SupervisorEvent] {
        var events: [SupervisorEvent] = []
        while events.count < count, let event = await iterator.next() { events.append(event) }
        return events
    }

    /// The next `count` connection changes, skipping every other event.
    mutating func connectionStates(_ count: Int) async -> [ConnectionState] {
        var states: [ConnectionState] = []
        while states.count < count, let event = await iterator.next() {
            if case .connection(let state) = event { states.append(state) }
        }
        return states
    }
}

/// A `VirtualClock` that also records every duration it was asked to sleep for.
private final class RecordingClock: MWSupport.Clock, @unchecked Sendable {
    let base = VirtualClock()
    private let lock = NSLock()
    private var durations: [Duration] = []

    var now: TimeInterval { base.now }
    var sleeps: [Duration] { lock.withLock { durations } }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        lock.withLock { durations.append(duration) }
        try await base.sleep(for: duration)
    }
}

/// Hands out `FakeMeetingEngineProvider`'s engines behind a wrapper that counts starts and
/// finishes, so a test can await a reopened session instead of polling.
private final class AnnouncingProvider: MeetingEngineProviding, @unchecked Sendable {
    let fakes = FakeMeetingEngineProvider()
    let started = Arrivals()
    let finished = Arrivals()
    private let clock: VirtualClock
    private let lock = NSLock()
    private var starts: [Double] = []

    init(clock: VirtualClock) {
        self.clock = clock
    }

    /// The clock time at each session's start, oldest first.
    var startTimes: [Double] { lock.withLock { starts } }

    func makeMeeting(_ engine: MeetingEngine, key: String, hints: RecognitionHints) -> any StreamingEngine {
        AnnouncingEngine(inner: fakes.makeMeeting(engine, key: key, hints: hints), provider: self)
    }

    fileprivate func didStart() {
        lock.withLock { starts.append(clock.now) }
        started.arrive()
    }
}

private final class AnnouncingEngine: StreamingEngine {
    let inner: any StreamingEngine
    let provider: AnnouncingProvider

    init(inner: any StreamingEngine, provider: AnnouncingProvider) {
        self.inner = inner
        self.provider = provider
    }

    var name: EngineName { inner.name }

    func start(sink: any TranscriptSink) {
        inner.start(sink: sink)
        provider.didStart()
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        inner.feed(buffer)
    }

    func finish(timeout: Duration) async -> StreamResult {
        let result = await inner.finish(timeout: timeout)
        provider.finished.arrive()
        return result
    }
}

/// A counter a test can await reaching a value.
private final class Arrivals: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var waiters: [(needed: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func arrive() {
        let ready = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            count += 1
            defer { waiters.removeAll { $0.needed <= count } }
            return waiters.filter { $0.needed <= count }.map(\.continuation)
        }
        for waiter in ready { waiter.resume() }
    }

    func wait(for needed: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let reached = lock.withLock { () -> Bool in
                guard count < needed else { return true }
                waiters.append((needed: needed, continuation: continuation))
                return false
            }
            if reached { continuation.resume() }
        }
    }
}
