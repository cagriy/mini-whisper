import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWSupport
import MWTestCall

/// The conductor as the session drives it: `TestCallConductor`, or a fake in AppTests, which
/// cannot reach `VirtualClock`.
@MainActor
protocol TestCallConducting: AnyObject {
    var events: AsyncStream<ConductorEvent> { get }
    var result: TestCallRun { get }
    func run() async
    func skip()
    func end(_ reason: EndReason)
}

extension TestCallConductor: TestCallConducting {}

/// What test calls need beyond the meeting controller. `AppDelegate` wires the real ones.
struct TestCallDependencies {
    /// A conductor on the system clock and random-number generator.
    var makeConductor: @MainActor (
        _ scenario: TestScenario, _ casting: [TestCallRole: CastVoice], _ overlap: Bool,
        _ player: any SpeechPlaying, _ sensor: any UserSpeechSensing
    ) -> any TestCallConducting
    /// A `say` player that stamps its runs with `meetingTime`.
    var makePlayer: @MainActor (_ meetingTime: @escaping @MainActor () -> Double) -> any SpeechPlaying
    /// The `say -v ?` listing, off the main actor.
    var loadVoices: @Sendable () async -> String
    /// The stored meetings' index rows, for the scenario menu's latest WERs.
    var index: @Sendable () throws -> [IndexEntry]
    /// A meeting's `testcall.json`, for Earlier runs.
    var readRecord: @Sendable (UUID) throws -> TestCallRecord?
}

/// What the setup page starts a test call with (design §5.5 step 2).
struct TestCallSetup: Equatable {
    /// Design §3 R5.
    static let voicesUnavailable = "Test calls need two English voices."
        + " Add one in System Settings → Accessibility → Spoken Content."

    var choice: ScenarioChoice
    var engine: MeetingEngine
    var overlap: Bool
    /// The voices listed when the chooser opened, which the scenario is cast onto.
    var voices: [SystemVoice]
}

/// The meeting's clock, the microphone gate and the tap, as the conductor reads them.
@MainActor
struct ControllerSpeechSensor: UserSpeechSensing {
    let controller: any MeetingControlling

    var meetingTime: Double { controller.meetingTime }
    var isSpeaking: Bool { controller.userSpeech.isSpeakingNow }
    var speechSpans: [ClosedRange<Double>] { controller.userSpeech.spans.map { $0.start...$0.end } }
    var lastAudibleSystemAudio: Double? { controller.lastAudibleSystemAudio }
}

/// One test call (design §5.1, §5.5): its conductor and `say` player, fed by the meeting's
/// speech, and the Stop order that scores every drained segment.
@MainActor
final class TestCallSession {
    let scenario: TestScenario
    private let controller: any MeetingControlling
    private let conductor: any TestCallConducting
    private let engine: MeetingEngine
    private let overlap: Bool
    private let log = Log.meeting
    private var run: Task<Void, Never>?
    private var finishing = false

    /// `controller` has started the meeting `scenario` is tagged on, cast as `casting`.
    init(
        controller: any MeetingControlling,
        scenario: TestScenario,
        casting: [TestCallRole: CastVoice],
        engine: MeetingEngine,
        overlap: Bool,
        deps: TestCallDependencies
    ) {
        self.controller = controller
        self.scenario = scenario
        self.engine = engine
        self.overlap = overlap
        conductor = deps.makeConductor(
            scenario, casting, overlap, deps.makePlayer { controller.meetingTime },
            ControllerSpeechSensor(controller: controller)
        )
    }

    /// Plays the script once the meeting records (design §5.5 step 3).
    func start() {
        guard run == nil else { return }
        log.info(
            "test call: start scenario=\(scenario.id) rev=\(scenario.revision) engine=\(engine.rawValue) overlap=\(overlap)"
        )
        run = Task { await self.conductor.run() }
    }

    func skip() {
        conductor.skip()
    }

    /// The meeting paused for sleep: the script ends, and Stop then scores it (R12).
    func macSlept() {
        conductor.end(.sleep)
    }

    /// Design §5.5 Stop: the script ends first and its run returns, so no voice speaks into the
    /// drain and the result is final; the score follows the drain; the summary comes last,
    /// except on quit.
    func finish(summarise: Bool) async {
        guard !finishing else { return }
        finishing = true
        conductor.end(.stop)
        await run?.value
        await controller.stop(summarise: false)
        await controller.finishTest(conductor.result, scenario: scenario)
        if summarise { await controller.summarise() }
    }
}
