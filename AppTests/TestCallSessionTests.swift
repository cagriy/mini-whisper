import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWSupport
import MWTestCall
import Testing
@testable import MiniWhisper

/// The fakes' calls, in the order they were made.
@MainActor
final class CallLog {
    private(set) var calls: [String] = []

    func append(_ call: String) { calls.append(call) }
}

/// A conductor whose `run()` lasts until `end(_:)`, as a script still playing does.
@MainActor
final class FakeConductor: TestCallConducting {
    let events: AsyncStream<ConductorEvent>
    let result = TestCallRun(
        lines: [RunLine(index: 1, role: .a, status: .done, start: 0, end: 2)], casting: [:], overlap: false
    )
    private(set) var ends: [EndReason] = []
    private let log: CallLog
    private let continuation: AsyncStream<ConductorEvent>.Continuation
    private var running = false
    private var ended: CheckedContinuation<Void, Never>?
    private var runWaiters: [CheckedContinuation<Void, Never>] = []

    init(log: CallLog = CallLog()) {
        self.log = log
        (events, continuation) = AsyncStream.makeStream()
    }

    func run() async {
        log.append("run")
        running = true
        runWaiters.forEach { $0.resume() }
        runWaiters = []
        if ends.isEmpty { await withCheckedContinuation { ended = $0 } }
        log.append("run returned")
    }

    func skip() { log.append("skip") }

    func send(_ event: ConductorEvent) { continuation.yield(event) }

    func end(_ reason: EndReason) {
        log.append("end(\(reason))")
        ends.append(reason)
        ended?.resume()
        ended = nil
        continuation.finish()
    }

    /// Returns once `run()` has begun.
    func started() async {
        guard !running else { return }
        await withCheckedContinuation { runWaiters.append($0) }
    }
}

@MainActor
final class FakePlayer: SpeechPlaying {
    func play(_ line: VoiceLine) async -> Playback { Playback(launched: 0, exited: 0, normalExit: true) }
    func stop() {}
}

/// `stop`, `finishTest` and `summarise` into the shared log; the sensor's readings as set.
@MainActor
private final class StubController: MeetingControlling {
    let events: AsyncStream<MeetingEvent>
    var state: MeetingState = .recording
    var meeting: Meeting?
    var meetingTime = 0.0
    var userSpeech = SpeechGate.View()
    var lastAudibleSystemAudio: Double?
    private(set) var finished: [(run: TestCallRun, scenario: TestScenario)] = []
    private let log: CallLog

    init(log: CallLog) {
        self.log = log
        events = AsyncStream { _ in }
    }

    func start(mode: MeetingMode, title: String, engine: MeetingEngine?, test: TestCallTag?) async throws {}

    func stop(summarise: Bool) async {
        log.append("stop(\(summarise))")
        state = .stopped
    }

    func finishTest(_ run: TestCallRun, scenario: TestScenario) async {
        log.append("finishTest")
        finished.append((run, scenario))
    }

    func summarise() async { log.append("summarise") }
    func regenerateSummary() async {}
    func pause() async {}
    func resume() async {}
    func rename(speaker: Int, to name: String) async {}
    func addNote(_ text: String, firstKeystrokeAt time: Double) async {}
    func open(_ id: UUID) async throws {}
    func edit(segment: UUID, text: String) async {}
    func reassign(segment: UUID, to speaker: Int) async {}
    func retitle(_ title: String) async {}
}

/// Collects log messages; AppTests cannot reach `MWTestSupport`'s capturing sink.
final class MessageSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var messages: [String] { lock.withLock { stored } }

    func write(_ record: LogRecord) {
        lock.withLock { stored.append(record.message) }
    }
}

/// `Log.withSinks` around a main-actor body.
func logging(to sink: MessageSink, _ body: @MainActor @Sendable () async -> Void) async {
    await Log.withSinks(debug: true, sinks: [sink]) { await body() }
}

@MainActor
@Suite struct TestCallSessionTests {
    private static let scenario = TestScenario(
        id: "harbour-survey", revision: 2, title: "Harbour survey",
        voices: [
            VoiceRole(role: .a, character: "Ines", requested: "Moira"),
            VoiceRole(role: .b, character: "Okafor", requested: "Rishi"),
        ],
        lines: [
            ScenarioLine(role: .a, text: "Lighthouse lanterns flicker beyond the breakwater."),
            ScenarioLine(role: .you, text: "Trawlers anchor near the quayside tonight."),
        ]
    )
    private static let casting: [TestCallRole: CastVoice] = [
        .a: CastVoice(role: .a, character: "Ines", requested: "Moira", voice: "Moira"),
        .b: CastVoice(role: .b, character: "Okafor", requested: "Rishi", voice: "Rishi"),
    ]

    /// What the session handed the conductor factory.
    private final class Made {
        var player: (any SpeechPlaying)?
        var sensor: (any UserSpeechSensing)?
        var scenario: TestScenario?
        var casting: [TestCallRole: CastVoice]?
        var overlap: Bool?
        var meetingTime: (@MainActor () -> Double)?
    }

    private func session(
        _ controller: StubController, _ conductor: FakeConductor, made: Made = Made()
    ) -> TestCallSession {
        TestCallSession(
            controller: controller, scenario: Self.scenario, casting: Self.casting, engine: .assemblyaiStreaming,
            overlap: true,
            deps: TestCallDependencies(
                makeConductor: { scenario, casting, overlap, player, sensor in
                    made.scenario = scenario
                    made.casting = casting
                    made.overlap = overlap
                    made.player = player
                    made.sensor = sensor
                    return conductor
                },
                makePlayer: { meetingTime in
                    made.meetingTime = meetingTime
                    return FakePlayer()
                },
                loadVoices: { "" },
                index: { [] },
                readRecord: { _ in nil }
            )
        )
    }

    @Test func stopRunsEndStopScoreThenSummarise() async {
        let log = CallLog()
        let controller = StubController(log: log)
        let conductor = FakeConductor(log: log)
        let session = session(controller, conductor)
        session.start()
        await conductor.started()

        await session.finish(summarise: true)

        // The run has returned before Stop, so the result read is final.
        #expect(log.calls == ["run", "end(stop)", "run returned", "stop(false)", "finishTest", "summarise"])
        #expect(controller.finished.map(\.run) == [conductor.result])
        #expect(controller.finished.map(\.scenario) == [Self.scenario])
    }

    @Test func quitPathSkipsTheSummary() async {
        let log = CallLog()
        let session = session(StubController(log: log), FakeConductor(log: log))
        session.start()

        await session.finish(summarise: false)

        #expect(log.calls.filter { !$0.hasPrefix("run") } == ["end(stop)", "stop(false)", "finishTest"])
    }

    @Test func stopTwiceScoresOnce() async {
        let log = CallLog()
        let controller = StubController(log: log)
        let session = session(controller, FakeConductor(log: log))
        session.start()

        await session.finish(summarise: true)
        await session.finish(summarise: true)

        #expect(controller.finished.count == 1)
    }

    @Test func sleepEndsTheScriptWithSleep() async {
        let conductor = FakeConductor()
        let session = session(StubController(log: CallLog()), conductor)
        session.start()

        session.macSlept()

        #expect(conductor.ends == [.sleep])
        await session.finish(summarise: false)
    }

    @Test func conductorEventsAndSleepReachThePane() async {
        let conductor = FakeConductor()
        let session = session(StubController(log: CallLog()), conductor)
        #expect(session.pane.scenario == Self.scenario)
        #expect(session.pane.title == "Script · Harbour survey")
        session.start()

        conductor.send(.line(1, .voiceSpeaking(.a)))
        await until { session.pane.current != nil }
        #expect(session.pane.turnTag?.text == "Ines · Moira voice · speaking")

        conductor.send(.captureMissing(1))
        conductor.send(.line(2, .yourTurn))
        await until { session.pane.current?.number == 2 }
        #expect(session.pane.notices.count == 1)

        session.macSlept()
        #expect(session.pane.hint == "The test call ended when the Mac slept. Press Stop for the score.")
        await session.finish(summarise: false)
    }

    /// The session forwards events on its own task; this yields until they have arrived.
    private func until(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
    }

    @Test func skipReachesTheConductor() async {
        let log = CallLog()
        let session = session(StubController(log: log), FakeConductor(log: log))

        session.skip()

        #expect(log.calls == ["skip"])
    }

    @Test func sensorReadsTheController() throws {
        let controller = StubController(log: CallLog())
        let made = Made()
        _ = session(controller, FakeConductor(), made: made)
        controller.meetingTime = 12.5
        controller.userSpeech = SpeechGate.View(
            spans: [SpeechSpan(start: 1, end: 2), SpeechSpan(start: 3, end: 4.5)], isSpeakingNow: true
        )
        controller.lastAudibleSystemAudio = 9

        let sensor = try #require(made.sensor)
        #expect(sensor.meetingTime == 12.5)
        #expect(sensor.isSpeaking)
        #expect(sensor.speechSpans == [1...2, 3...4.5])
        #expect(sensor.lastAudibleSystemAudio == 9)
        #expect(made.meetingTime?() == 12.5)
        #expect(made.player != nil)
        #expect(made.scenario == Self.scenario)
        #expect(made.casting == Self.casting)
        #expect(made.overlap == true)
    }

    /// R27: ids and settings only.
    @Test func startLogLineCarriesIdsOnly() async {
        let sink = MessageSink()
        let session = session(StubController(log: CallLog()), FakeConductor())

        await logging(to: sink) { session.start() }

        #expect(sink.messages == [
            "test call: start scenario=harbour-survey rev=2 engine=assemblyai_streaming overlap=true",
        ])
        let words = Self.scenario.lines.flatMap { $0.text.lowercased().split { !$0.isLetter } }.filter { $0.count >= 4 }
        for message in sink.messages.map({ $0.lowercased() }) {
            #expect(!words.contains { message.contains($0) }, "\(message)")
        }
        await session.finish(summarise: false)
    }
}
