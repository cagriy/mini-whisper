import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWTestCall
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
        var starts: [(mode: MeetingMode, title: String, engine: MeetingEngine?, test: TestCallTag?)] = []
        var stops: [Bool] = []
        var finishTests = 0
        var summarises = 0
        /// The window's stopped-state requests, in arrival order.
        let requests: AsyncStream<String>
        private let request: AsyncStream<String>.Continuation

        init() {
            (events, continuation) = AsyncStream.makeStream()
            (requests, request) = AsyncStream.makeStream()
        }

        var meetingTime = 0.0
        var userSpeech = SpeechGate.View()
        var lastAudibleSystemAudio: Double?

        func start(mode: MeetingMode, title: String, engine: MeetingEngine?, test: TestCallTag?) async throws {
            starts.append((mode, title, engine, test))
            state = .recording
            meeting = Meeting(title: title, startedAt: MeetingCoordinatorTests.now, mode: mode,
                              engine: engine ?? .speechmaticsStandard, userName: "Alex", test: test)
        }

        func stop(summarise: Bool) async {
            stops.append(summarise)
            state = .stopped
            meeting?.endedAt = MeetingCoordinatorTests.now.addingTimeInterval(2932)
            meeting?.durationSeconds = 2932
            continuation.yield(.state(.stopped))
        }

        func finishTest(_ run: TestCallRun, scenario: TestScenario) async { finishTests += 1 }
        func pause() async { state = .paused(.user) }
        func resume() async { state = .recording }
        func rename(speaker: Int, to name: String) async {}
        func addNote(_ text: String, firstKeystrokeAt time: Double) async {}
        func open(_ id: UUID) async throws {
            meeting = Meeting(id: id, title: "Standup", startedAt: MeetingCoordinatorTests.now,
                              endedAt: MeetingCoordinatorTests.now.addingTimeInterval(600), durationSeconds: 600,
                              mode: .inRoom, engine: .speechmaticsStandard, userName: "Alex")
            state = .stopped
            continuation.yield(.state(.stopped))
        }

        func summarise() async {
            summarises += 1
            request.yield("summarise")
        }

        func send(_ event: MeetingEvent) { continuation.yield(event) }
        func edit(segment: UUID, text: String) async { request.yield("edit \(text)") }
        func reassign(segment: UUID, to speaker: Int) async { request.yield("reassign \(speaker)") }
        func retitle(_ title: String) async { request.yield("retitle \(title)") }
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
        var models: [MeetingWindowModel] = []
        var actions: [MeetingActions] = []
        var exports: [(kind: MeetingExporter.Kind, id: UUID)] = []
        var conductors: [FakeConductor] = []
        /// The conductors' calls.
        let conductorLog = CallLog()
        /// What each test call's conductor was built for.
        var made: [(scenario: TestScenario, casting: [TestCallRole: CastVoice], overlap: Bool)] = []
        var changeCount = 0
        let changes: AsyncStream<Void>
        private let change: AsyncStream<Void>.Continuation
        var frontApps: [String?] = []
        var log: [String] = []
        var frontApp: String? = "Zoom"
        /// Starts the controller had seen each time a dictation was ended.
        var startsWhenDictationEnded: [Int] = []
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
            makeWindow: { [unowned self] model, actions in
                log.append("window")
                models.append(model)
                self.actions.append(actions)
                let window = StubWindow()
                windows.append(window)
                return window
            },
            now: { MeetingCoordinatorTests.now },
            endDictation: { [unowned self] in
                startsWhenDictationEnded.append(controllers.last?.starts.count ?? -1)
            },
            openSettings: {},
            export: { [unowned self] kind, id in exports.append((kind, id)) },
            changed: { [unowned self] in
                changeCount += 1
                change.yield()
            },
            testCalls: TestCallDependencies(
                makeConductor: { [unowned self] scenario, casting, overlap, _, _ in
                    made.append((scenario, casting, overlap))
                    let conductor = FakeConductor(log: conductorLog)
                    conductors.append(conductor)
                    return conductor
                },
                makePlayer: { _ in FakePlayer() },
                loadVoices: { "" },
                index: { [] },
                readRecord: { _ in nil }
            )
        ))

        init() {
            (changes, change) = AsyncStream.makeStream()
        }

        /// A recorded meeting, stopped, once the window has taken the stop.
        func stopped() async -> StubController {
            let controller = await recording()
            await coordinator.stop()
            for await _ in changes where controller.state == .stopped && models[0].state == .stopped { break }
            return controller
        }

        /// A meeting opened from the chooser and started.
        func recording() async -> StubController {
            await coordinator.toggle()
            await coordinator.start()
            return controllers[0]
        }

        /// A test call started from the chooser.
        func testCall(_ setup: TestCallSetup = MeetingCoordinatorTests.setup()) async -> StubController {
            await coordinator.toggle()
            await coordinator.startTestCall(setup)
            return controllers[0]
        }
    }

    private static let voices = [SystemVoice(name: "Daniel", locale: "en_GB"), SystemVoice(name: "Karen", locale: "en_AU")]

    private static func setup(voices: [SystemVoice] = voices) -> TestCallSetup {
        TestCallSetup(choice: .named("sprint-planning"), engine: .assemblyaiStreaming, overlap: true, voices: voices)
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
        #expect(harness.controllers[0].starts.map(\.engine) == [nil])
        #expect(harness.controllers[0].starts.map(\.test) == [nil])
    }

    @Test func startEndsAnInFlightDictationFirst() async {
        let harness = Harness()
        await harness.coordinator.toggle()
        #expect(harness.startsWhenDictationEnded.isEmpty)

        let controller = await harness.recording()

        #expect(harness.startsWhenDictationEnded == [0])
        #expect(controller.starts.count == 1)
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

    @Test func stoppedMeetingShowsItsEndInTheHeader() async {
        let harness = Harness()
        _ = await harness.stopped()

        let model = harness.models[0]
        #expect(model.elapsedText == "00:48:52")
        #expect(model.endedChip != nil)
        #expect(harness.windows[0].title == "Meeting")
    }

    @Test func windowRequestsReachTheController() async {
        let harness = Harness()
        let controller = await harness.stopped()
        let actions = harness.actions[0]
        let segment = UUID()

        actions.summarise()
        actions.edit(segment, "Agreed!")
        actions.reassign(segment, 2)
        actions.retitle(" Northwind rollout sync ")
        actions.retitle("Northwind rollout sync")

        var requests: [String] = []
        for await request in controller.requests {
            requests.append(request)
            if requests.count == 4 { break }
        }
        #expect(Set(requests) == ["summarise", "edit Agreed!", "reassign 2", "retitle Northwind rollout sync"])
        #expect(harness.models[0].title == "Northwind rollout sync")
    }

    @Test func headerRenameNotifiesTheList() async {
        let harness = Harness()
        let controller = await harness.stopped()
        let before = harness.changeCount
        var requests = controller.requests.makeAsyncIterator()

        harness.actions[0].retitle("Northwind rollout sync")

        #expect(await requests.next() == "retitle Northwind rollout sync")
        #expect(harness.changeCount == before + 1)
    }

    @Test func exportNamesTheMeeting() async throws {
        let harness = Harness()
        let controller = await harness.stopped()

        harness.actions[0].export(.both)

        let id = try #require(controller.meeting?.id)
        #expect(harness.exports.map(\.kind) == [.both])
        #expect(harness.exports.map(\.id) == [id])
    }

    @Test func openShowsAStoredMeetingInItsOwnWindow() async throws {
        let harness = Harness()
        let id = UUID()

        try await harness.coordinator.open(id)
        for await _ in harness.changes where !harness.windows.isEmpty { break }

        #expect(harness.windows.map(\.shows) == [1])
        #expect(harness.windows.first?.title == "Meeting")
        #expect(harness.models.first?.state == .stopped)
        #expect(harness.models.first?.title == "Standup")
        #expect(harness.frontApps == [nil])
        #expect(harness.coordinator.isOpen(id))
        #expect(harness.coordinator.isActive == false)

        try await harness.coordinator.open(id)
        #expect(harness.controllers.count == 1)
        #expect(harness.windows.map(\.shows) == [2])

        harness.actions[0].closed()
        #expect(harness.coordinator.isOpen(id) == false)
    }

    @Test func listRenameOfAnOpenMeetingGoesThroughItsController() async throws {
        let harness = Harness()
        let id = UUID()
        try await harness.coordinator.open(id)
        for await _ in harness.changes where !harness.windows.isEmpty { break }

        #expect(await harness.coordinator.retitle(id, to: "Daily standup"))
        #expect(await harness.coordinator.retitle(UUID(), to: "Other") == false)

        var requests = harness.controllers[0].requests.makeAsyncIterator()
        #expect(await requests.next() == "retitle Daily standup")
        #expect(harness.models[0].title == "Daily standup")
    }

    // MARK: - Test calls

    @Test func startTestCallStartsARemoteMeetingWithTitleEngineAndTag() async throws {
        let harness = Harness()

        let controller = await harness.testCall()

        #expect(controller.starts.map(\.mode) == [.remote])
        #expect(controller.starts.map(\.title) == ["Test call · Sprint planning"])
        #expect(controller.starts.map(\.engine) == [.assemblyaiStreaming])
        #expect(controller.starts.map(\.test) == [
            TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning", wer: nil),
        ])
        #expect(harness.startsWhenDictationEnded == [0])
        #expect(harness.models[0].title == "Test call · Sprint planning")
        let made = try #require(harness.made.first)
        #expect(made.scenario.id == "sprint-planning")
        #expect(made.casting[.a]?.voice == "Daniel")
        #expect(made.casting[.b]?.voice == "Karen")
        #expect(made.overlap)
        await try #require(harness.conductors.first).started()
    }

    @Test func startTestCallWithUnavailableVoicesShowsTheVoiceMessage() async {
        let harness = Harness()

        let controller = await harness.testCall(Self.setup(voices: [SystemVoice(name: "Daniel", locale: "en_GB")]))

        #expect(controller.starts.isEmpty)
        #expect(harness.conductors.isEmpty)
        #expect(harness.models[0].errorMessage
            == "Test calls need two English voices. Add one in System Settings → Accessibility → Spoken Content.")
    }

    @Test func stopAndQuitGoThroughTheSession() async throws {
        let stopping = Harness()
        let stopped = await stopping.testCall()
        await stopping.coordinator.stop()

        #expect(try #require(stopping.conductors.first).ends == [.stop])
        #expect(stopped.stops == [false])
        #expect(stopped.finishTests == 1)
        #expect(stopped.summarises == 1)

        let quitting = Harness()
        let quit = await quitting.testCall()
        await quitting.coordinator.stop(summarise: false)

        #expect(try #require(quitting.conductors.first).ends == [.stop])
        #expect(quit.stops == [false])
        #expect(quit.finishTests == 1)
        #expect(quit.summarises == 0)
    }

    @Test func sleepEventReachesTheSession() async throws {
        let harness = Harness()
        let controller = await harness.testCall()
        let conductor = try #require(harness.conductors.first)

        controller.state = .paused(.sleep)
        controller.send(.state(.paused(.sleep)))

        for await _ in harness.changes where !conductor.ends.isEmpty { break }
        #expect(conductor.ends == [.sleep])
    }

    @Test func testCallWindowShowsTheSessionsScriptAndSkipsLines() async throws {
        let harness = Harness()
        _ = await harness.testCall()

        let pane = try #require(harness.models[0].testCall)
        #expect(pane.scenario.id == "sprint-planning")
        #expect(pane.casting[.b]?.voice == "Karen")
        harness.actions[0].skipLine()

        #expect(harness.conductorLog.calls.contains("skip"))
    }

    @Test func ordinaryMeetingsStopAsBefore() async {
        let harness = Harness()
        let controller = await harness.recording()

        await harness.coordinator.stop()

        #expect(controller.stops == [true])
        #expect(controller.finishTests == 0)
        #expect(harness.conductors.isEmpty)
    }
}
