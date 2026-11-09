import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct MeetingCoordinatorTests {
    private static let now = Date(timeIntervalSince1970: 1_794_234_600)

    @MainActor
    private final class StubController: MeetingControlling {
        let events: AsyncStream<MeetingEvent>
        private let continuation: AsyncStream<MeetingEvent>.Continuation
        var state: MeetingState = .idle
        var meeting: Meeting?
        var starts: [(mode: MeetingMode, title: String)] = []
        var stops: [Bool] = []

        init() {
            (events, continuation) = AsyncStream.makeStream()
        }

        func start(mode: MeetingMode, title: String) async throws {
            starts.append((mode, title))
            state = .recording
            meeting = Meeting(title: title, startedAt: MeetingCoordinatorTests.now, mode: mode,
                              engine: .speechmaticsStandard, userName: "Alex")
        }

        func stop(summarise: Bool) async {
            stops.append(summarise)
            state = .stopped
        }

        func pause() async { state = .paused(.user) }
        func resume() async { state = .recording }
        func rename(speaker: Int, to name: String) async {}
        func addNote(_ text: String, firstKeystrokeAt time: Double) async {}
    }

    @MainActor
    private final class StubWindow: MeetingWindowPresenting {
        var shows = 0
        var closes = 0
        var isVisible = false
        var title = ""

        func show() {
            shows += 1
            isVisible = true
        }

        func close() {
            closes += 1
            isVisible = false
        }

        func setTitle(_ title: String) { self.title = title }
    }

    @MainActor
    private final class Harness {
        var controllers: [StubController] = []
        var windows: [StubWindow] = []
        var frontApps: [String?] = []
        var log: [String] = []
        var frontApp: String? = "Zoom"
        lazy var coordinator = MeetingCoordinator(deps: MeetingCoordinator.Dependencies(
            makeController: { [unowned self] frontApp in
                frontApps.append(frontApp)
                let controller = StubController()
                controllers.append(controller)
                return controller
            },
            frontApp: { [unowned self] in
                log.append("front app")
                return frontApp
            },
            chooser: {
                MeetingWindowModel.Chooser(
                    config: Config(), platform: PlatformInfo(osMajor: 26, osMinor: 0), accountName: "Alex",
                    hasKey: { $0 == .speechmatics }
                )
            },
            makeWindow: { [unowned self] _, _ in
                log.append("window")
                let window = StubWindow()
                windows.append(window)
                return window
            },
            now: { MeetingCoordinatorTests.now },
            openSettings: {},
            changed: {}
        ))

        /// A meeting opened from the chooser and started.
        func recording() async -> StubController {
            await coordinator.toggle()
            await coordinator.start()
            return controllers[0]
        }
    }

    @Test func firstPressOpensTheChooser() async {
        let harness = Harness()
        await harness.coordinator.toggle()

        #expect(harness.controllers.count == 1)
        #expect(harness.windows.map(\.shows) == [1])
        #expect(harness.windows.first?.title == "New Meeting")
        #expect(harness.coordinator.isActive == false)
    }

    @Test func pressWhileTheChooserIsOpenIsIgnored() async {
        let harness = Harness()
        await harness.coordinator.toggle()
        await harness.coordinator.toggle()

        #expect(harness.controllers.count == 1)
        #expect(harness.windows.map(\.shows) == [1])
        #expect(harness.controllers[0].starts.isEmpty)
    }

    @Test func pressWhileRecordingStops() async {
        let harness = Harness()
        let controller = await harness.recording()
        #expect(harness.coordinator.isActive)

        await harness.coordinator.toggle()

        #expect(controller.stops == [true])
        #expect(harness.controllers.count == 1)
    }

    @Test func pressWhilePausedStops() async {
        let harness = Harness()
        let controller = await harness.recording()
        controller.state = .paused(.sleep)

        await harness.coordinator.toggle()

        #expect(controller.stops == [true])
    }

    @Test func pressWhileStoppingIsIgnored() async {
        let harness = Harness()
        let controller = await harness.recording()
        controller.state = .stopping

        await harness.coordinator.toggle()

        #expect(controller.stops.isEmpty)
        #expect(harness.controllers.count == 1)
    }

    @Test func pressAfterTheMeetingStoppedOpensANewChooser() async {
        let harness = Harness()
        let controller = await harness.recording()
        await harness.coordinator.stop()
        #expect(controller.stops == [true])

        await harness.coordinator.toggle()

        #expect(harness.controllers.count == 2)
        #expect(harness.windows.map(\.shows) == [1, 1])
    }

    @Test func chooserCapturesTheFrontAppBeforeItOpens() async {
        let harness = Harness()
        await harness.coordinator.toggle()
        harness.frontApp = "Mini Whisper"
        await harness.coordinator.start()

        #expect(harness.log == ["front app", "window"])
        #expect(harness.frontApps == ["Zoom"])
        #expect(harness.controllers[0].starts.map(\.title) == [MeetingTitle.default(app: "Zoom", date: Self.now)])
        #expect(harness.controllers[0].starts.map(\.mode) == [.remote])
    }

    @Test func quitWhileActiveNeedsConfirmation() async {
        let harness = Harness()
        #expect(harness.coordinator.needsQuitConfirmation == false)
        await harness.coordinator.toggle()
        #expect(harness.coordinator.needsQuitConfirmation == false)

        await harness.coordinator.start()
        #expect(harness.coordinator.needsQuitConfirmation)
        harness.controllers[0].state = .paused(.user)
        #expect(harness.coordinator.needsQuitConfirmation)
        harness.controllers[0].state = .stopped
        #expect(harness.coordinator.needsQuitConfirmation == false)
    }

    @Test func confirmedQuitStopsWithoutSummary() async {
        let harness = Harness()
        let controller = await harness.recording()

        await harness.coordinator.stop(summarise: false)

        #expect(controller.stops == [false])
        #expect(harness.coordinator.needsQuitConfirmation == false)
    }
}
