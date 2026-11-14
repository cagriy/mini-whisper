import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWTestCall
import Testing
@testable import MiniWhisper

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MeetingCoordinatorTests {
    private nonisolated static let now = Date(timeIntervalSince1970: 1_794_234_600)

    /// Holds a call until `open()`; opening first lets the call through.
    @MainActor
    private final class Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    @MainActor
    private final class StubController: MeetingControlling {
        struct OpenFailed: Error {}

        let events: AsyncStream<MeetingEvent>
        private let continuation: AsyncStream<MeetingEvent>.Continuation
        var state: MeetingState = .idle
        var meeting: Meeting?
        var starts: [(mode: MeetingMode, title: String, engine: MeetingEngine?, test: TestCallTag?)] = []
        var stops: [Bool] = []
        var finishTests = 0
        var summarises = 0
        /// Every event sent, in order.
        private(set) var emitted: [MeetingEvent] = []
        /// Holds `start` before the meeting starts.
        var startGate: Gate?
        /// Holds `stop` after its events: `MeetingController.stop` returns once its summary is written.
        var stopGate: Gate?
        /// Sent after `.state(.stopped)` by a stop that summarises, as `MeetingController.stop` does.
        var summaryOnStop: SummaryState?
        var failsToOpen = false
        /// The page's stopped-state requests, in arrival order.
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
            await startGate?.wait()
            state = .recording
            meeting = Meeting(title: title, startedAt: MeetingCoordinatorTests.now, mode: mode,
                              engine: engine ?? .speechmaticsStandard, userName: "Alex", test: test)
        }

        func stop(summarise: Bool) async {
            stops.append(summarise)
            state = .stopped
            meeting?.endedAt = MeetingCoordinatorTests.now.addingTimeInterval(2932)
            meeting?.durationSeconds = 2932
            send(.state(.stopped))
            if summarise, let summaryOnStop { send(.summary(summaryOnStop)) }
            await stopGate?.wait()
        }

        func finishTest(_ run: TestCallRun, scenario: TestScenario) async { finishTests += 1 }
        func pause() async { state = .paused(.user) }
        func resume() async { state = .recording }
        func rename(speaker: Int, to name: String) async {}
        func addNote(_ text: String, firstKeystrokeAt time: Double) async {}
        func open(_ id: UUID) async throws {
            if failsToOpen { throw OpenFailed() }
            meeting = Meeting(id: id, title: "Standup", startedAt: MeetingCoordinatorTests.now,
                              endedAt: MeetingCoordinatorTests.now.addingTimeInterval(600), durationSeconds: 600,
                              mode: .inRoom, engine: .speechmaticsStandard, userName: "Alex")
            state = .stopped
            send(.state(.stopped))
        }

        func summarise() async {
            summarises += 1
            request.yield("summarise")
        }

        func regenerateSummary() async { request.yield("regenerate") }

        func send(_ event: MeetingEvent) {
            emitted.append(event)
            continuation.yield(event)
        }

        func edit(segment: UUID, text: String) async { request.yield("edit \(text)") }
        func reassign(segment: UUID, to speaker: Int) async { request.yield("reassign \(speaker)") }
        func retitle(_ title: String) async { request.yield("retitle \(title)") }
    }

    /// The stored meetings and `say -v ?` listing the test-call readers see, and how they were read.
    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [IndexEntry] = []
        private var records: [UUID: TestCallRecord] = [:]
        private var readsOnMain: [Bool] = []
        private var listing = ""
        private var listings = 0

        var reads: [Bool] { lock.withLock { readsOnMain } }
        var voiceLoads: Int { lock.withLock { listings } }

        func setListing(_ listing: String) {
            lock.withLock { self.listing = listing }
        }

        func loadVoices() -> String {
            lock.withLock {
                listings += 1
                return listing
            }
        }

        func add(_ entry: IndexEntry, _ record: TestCallRecord) {
            lock.withLock {
                entries.append(entry)
                records[entry.id] = record
            }
        }

        func index() -> [IndexEntry] {
            lock.withLock { entries }
        }

        func read(_ id: UUID) -> TestCallRecord? {
            lock.withLock {
                readsOnMain.append(Thread.isMainThread)
                return records[id]
            }
        }
    }

    @MainActor
    private final class Harness {
        var controllers: [StubController] = []
        /// Every `present`, in order.
        var presented: [(model: MeetingWindowModel, actions: MeetingActions)] = []
        var dismissals = 0
        var exports: [(kind: MeetingExporter.Kind, id: UUID)] = []
        var copies: [MeetingWindowModel.CopyPayload] = []
        var settingsOpened: [SettingsModel.Section] = []
        var conductors: [FakeConductor] = []
        /// The conductors' calls.
        let conductorLog = CallLog()
        let store = Store()
        let clock = ManualClock()
        /// What each test call's conductor was built for.
        var made: [(scenario: TestScenario, casting: [TestCallRole: CastVoice], overlap: Bool)] = []
        var changeCount = 0
        let changes: AsyncStream<Void>
        private let change: AsyncStream<Void>.Continuation
        var frontApps: [String?] = []
        var log: [String] = []
        var frontApp: String? = "Zoom"
        /// The controllers made from now on fail to open a stored meeting.
        var opensFail = false
        /// Starts the controller had seen each time a dictation was ended.
        var startsWhenDictationEnded: [Int] = []
        lazy var coordinator: MeetingCoordinator = MeetingCoordinator(deps: MeetingCoordinator.Dependencies(
            makeController: { [unowned self] frontApp in
                frontApps.append(frontApp)
                let controller = StubController()
                controller.failsToOpen = opensFail
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
            present: { [unowned self] model, actions in
                log.append("present")
                presented.append((model, actions))
            },
            // The page goes away, as leaving it in the window does.
            dismiss: { [unowned self] in
                dismissals += 1
                coordinator.pageLeft()
            },
            now: { MeetingCoordinatorTests.now },
            clock: clock,
            endDictation: { [unowned self] in
                startsWhenDictationEnded.append(controllers.last?.starts.count ?? -1)
            },
            openSettings: { [unowned self] in settingsOpened.append($0) },
            export: { [unowned self] kind, id in exports.append((kind, id)) },
            copy: { [unowned self] in copies.append($0) },
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
                loadVoices: { [store] in store.loadVoices() },
                index: { [store] in store.index() },
                readRecord: { [store] in store.read($0) }
            )
        ))

        init() {
            (changes, change) = AsyncStream.makeStream()
        }

        /// Each model presented, once, in the order first presented.
        var models: [MeetingWindowModel] {
            presented.map(\.model).reduce(into: []) { models, model in
                if !models.contains(where: { $0 === model }) { models.append(model) }
            }
        }

        /// The actions each of `models` was first presented with.
        var actions: [MeetingActions] {
            models.compactMap { model in presented.first { $0.model === model }?.actions }
        }

        /// The model of the last `present`.
        var shownModel: MeetingWindowModel? { presented.last?.model }

        /// A recorded meeting, stopped while on the page, once its page has taken the stop.
        func stopped() async -> StubController {
            let controller = await recording()
            await coordinator.stop()
            await until { controller.state == .stopped && self.models[0].state == .stopped }
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

        /// A stored meeting opened from the list, once its page holds it.
        @discardableResult
        func open(_ id: UUID) async throws -> StubController {
            try await coordinator.open(id)
            let controller = try #require(controllers.last { $0.meeting?.id == id })
            let model = try #require(shownModel)
            await until { model.state == .stopped }
            return controller
        }

        /// Waits until the events the coordinator forwards have made `condition` true.
        func until(_ condition: @MainActor () -> Bool) async {
            guard !condition() else { return }
            for await _ in changes where condition() { break }
        }
    }

    private static let voices = [SystemVoice(name: "Daniel", locale: "en_GB"), SystemVoice(name: "Karen", locale: "en_AU")]

    private static func setup(voices: [SystemVoice] = voices) -> TestCallSetup {
        TestCallSetup(choice: .named("sprint-planning"), engine: .assemblyaiStreaming, overlap: true, voices: voices)
    }

    private nonisolated static let summary = Summary(
        text: "## Rollout\n- Ship on Friday", model: "claude-sonnet-4-5", createdAt: now,
        inputTokens: 1200, outputTokens: 300, costUSD: 0.02
    )

    // MARK: - Hotkey and chooser

    @Test func firstPressOpensTheChooser() async {
        let harness = Harness()
        await harness.coordinator.toggle()

        #expect(harness.controllers.count == 1)
        #expect(harness.presented.count == 1)
        #expect(harness.models.first?.state == .idle)
        #expect(harness.coordinator.isActive == false)
    }

    @Test func pressWhileTheChooserIsOpenIsIgnored() async {
        let harness = Harness()
        await harness.coordinator.toggle()
        await harness.coordinator.toggle()

        #expect(harness.controllers.count == 1)
        #expect(harness.presented.count == 1)
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
        #expect(harness.models.count == 2)
        #expect(harness.shownModel === harness.models[1])
    }

    @Test func chooserCapturesTheFrontAppBeforeItOpens() async {
        let harness = Harness()
        await harness.coordinator.toggle()
        harness.frontApp = "Mini Whisper"
        await harness.coordinator.start()

        #expect(harness.log == ["front app", "present"])
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
    }

    // MARK: - The page's requests

    @Test func pageRequestsReachTheController() async {
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

    @Test func regenerateActionCallsTheController() async throws {
        let harness = Harness()
        let controller = try await harness.open(UUID())
        var requests = controller.requests.makeAsyncIterator()

        harness.actions[0].regenerate()

        #expect(await requests.next() == "regenerate")
    }

    @Test func copyActionHandsThePayloadToCopy() async throws {
        let harness = Harness()
        let controller = try await harness.open(UUID())
        let model = harness.models[0]
        harness.actions[0].copySummary()
        #expect(harness.copies.isEmpty)

        controller.send(.summary(.ready(Self.summary)))
        await harness.until { model.copyPayload != nil }
        harness.actions[0].copySummary()

        #expect(harness.copies == [try #require(model.copyPayload)])
        #expect(harness.copies.first?.markdown == "# Standup\n\n## Rollout\n- Ship on Friday")
        #expect(model.justCopied)
        // `Copied` resets on the injected clock.
        for await _ in harness.clock.sleeps { break }
        harness.clock.wake()
        await model.copyReset?.value
        #expect(model.justCopied == false)
    }

    @Test func cancelAndBackDismiss() async throws {
        let harness = Harness()
        await harness.coordinator.toggle()

        harness.actions[0].cancel()

        #expect(harness.dismissals == 1)
        await harness.coordinator.toggle()
        #expect(harness.controllers.count == 2)

        let id = UUID()
        try await harness.open(id)
        harness.actions.last?.back()

        #expect(harness.dismissals == 2)
        #expect(harness.coordinator.isOpen(id) == false)
    }

    @Test func openSettingsSelectsMeetings() async {
        let harness = Harness()
        await harness.coordinator.toggle()

        harness.actions[0].openSettings()

        #expect(harness.settingsOpened == [.meetings])
    }

    // MARK: - Stored meetings

    @Test func openPresentsAStoredMeeting() async throws {
        let harness = Harness()
        let id = UUID()

        try await harness.open(id)

        #expect(harness.presented.count == 1)
        #expect(harness.models.first?.state == .stopped)
        #expect(harness.models.first?.title == "Standup")
        #expect(harness.frontApps == [nil])
        #expect(harness.coordinator.isOpen(id))
        #expect(harness.coordinator.isActive == false)

        try await harness.coordinator.open(id)
        #expect(harness.controllers.count == 1)
        #expect(harness.presented.count == 2)
        #expect(harness.shownModel === harness.models[0])

        harness.coordinator.pageLeft()
        #expect(harness.coordinator.isOpen(id) == false)
    }

    @Test func backDismissesTheMeetingPage() async throws {
        let harness = Harness()
        try await harness.open(UUID())

        harness.actions[0].back()

        #expect(harness.dismissals == 1)
        #expect(harness.presented.count == 1)
    }

    @Test func listRenameOfAnOpenMeetingGoesThroughItsController() async throws {
        let harness = Harness()
        let id = UUID()
        try await harness.open(id)

        #expect(await harness.coordinator.retitle(id, to: "Daily standup"))
        #expect(await harness.coordinator.retitle(UUID(), to: "Other") == false)

        var requests = harness.controllers[0].requests.makeAsyncIterator()
        #expect(await requests.next() == "retitle Daily standup")
        #expect(harness.models[0].title == "Daily standup")
    }

    // MARK: - Design §5.5, row by row

    @Test func openChooserShowsAnActiveMeeting() async {
        let harness = Harness()
        _ = await harness.recording()
        harness.coordinator.pageLeft()

        harness.coordinator.openChooser()

        #expect(harness.controllers.count == 1)
        #expect(harness.presented.count == 2)
        #expect(harness.shownModel === harness.models[0])
    }

    @Test func openChooserPresentsAnIdleChooserAgain() async {
        let harness = Harness()
        await harness.coordinator.toggle()

        harness.coordinator.openChooser()

        #expect(harness.controllers.count == 1)
        #expect(harness.presented.count == 2)
        #expect(harness.models.count == 1)
    }

    @Test func openChooserReleasesAStoppedCurrentAndOpened() async throws {
        let harness = Harness()
        let recorded = await harness.stopped()
        let recordedID = try #require(recorded.meeting?.id)
        #expect(harness.coordinator.isOpen(recordedID))

        harness.coordinator.openChooser()

        #expect(harness.coordinator.isOpen(recordedID) == false)
        #expect(harness.controllers.count == 2)
        #expect(harness.shownModel === harness.models[1])

        let stored = UUID()
        try await harness.open(stored)
        harness.coordinator.openChooser()

        #expect(harness.coordinator.isOpen(stored) == false)
        #expect(harness.controllers.count == 4)
        #expect(harness.shownModel === harness.models[3])
    }

    @Test func showPresentsTheCurrentMeetingOnlyWhileActive() async {
        let harness = Harness()
        harness.coordinator.show()
        #expect(harness.presented.isEmpty)

        await harness.coordinator.toggle()
        harness.coordinator.show()
        #expect(harness.presented.count == 1)

        await harness.coordinator.start()
        harness.coordinator.pageLeft()
        harness.coordinator.show()
        #expect(harness.presented.count == 2)
        #expect(harness.shownModel === harness.models[0])
    }

    @Test func openPresentsASessionAlreadyHoldingTheMeeting() async throws {
        let harness = Harness()
        let controller = await harness.recording()
        let id = try #require(controller.meeting?.id)
        harness.coordinator.pageLeft()

        try await harness.coordinator.open(id)

        #expect(harness.controllers.count == 1)
        #expect(harness.presented.count == 2)
        #expect(harness.shownModel === harness.models[0])
    }

    @Test func openPromotesAFinishingSessionAndReleasesThePreviousOpened() async throws {
        let harness = Harness()
        let first = UUID()
        let writing = try await harness.open(first)
        let firstModel = try #require(harness.shownModel)
        writing.send(.summary(.writing))
        await harness.until { firstModel.summary == .writing }
        harness.coordinator.pageLeft()
        #expect(harness.coordinator.isOpen(first))

        let second = UUID()
        try await harness.open(second)
        try await harness.coordinator.open(first)

        #expect(harness.controllers.count == 2)
        #expect(harness.shownModel === firstModel)
        #expect(harness.coordinator.isOpen(second) == false)
        // Opened now, so its summary no longer ends it.
        writing.send(.summary(.ready(Self.summary)))
        await harness.until { firstModel.summary == .ready(Self.summary) }
        #expect(harness.coordinator.isOpen(first))
    }

    @Test func openDropsAnIdleChooser() async throws {
        let harness = Harness()
        await harness.coordinator.toggle()

        try await harness.open(UUID())
        await harness.coordinator.toggle()

        #expect(harness.controllers.count == 3)
        #expect(harness.shownModel === harness.models[2])
    }

    @Test func openThatFailsLeavesThePageAsItWas() async throws {
        let harness = Harness()
        await harness.coordinator.toggle()
        harness.opensFail = true
        let id = UUID()

        await #expect(throws: StubController.OpenFailed.self) { try await harness.coordinator.open(id) }

        #expect(harness.presented.count == 1)
        #expect(harness.coordinator.isOpen(id) == false)
        // The chooser is still the current session.
        await harness.coordinator.toggle()
        #expect(harness.controllers.count == 2)
    }

    @Test func pageLeftDropsAnIdleChooser() async {
        let harness = Harness()
        await harness.coordinator.toggle()

        harness.coordinator.pageLeft()
        await harness.coordinator.toggle()

        #expect(harness.controllers.count == 2)
    }

    @Test func pageLeftKeepsAChooserWhoseStartIsUnderWay() async {
        let harness = Harness()
        await harness.coordinator.toggle()
        let gate = Gate()
        harness.controllers[0].startGate = gate
        let starting = Task { await harness.coordinator.start() }
        await until { !harness.controllers[0].starts.isEmpty }

        harness.coordinator.pageLeft()
        gate.open()
        await starting.value

        #expect(harness.coordinator.isActive)
        #expect(harness.coordinator.liveModel === harness.models[0])
    }

    @Test func pageLeftKeepsAnActiveMeeting() async throws {
        let harness = Harness()
        let controller = await harness.recording()

        harness.coordinator.pageLeft()

        #expect(harness.coordinator.isActive)
        #expect(harness.coordinator.isOpen(try #require(controller.meeting?.id)))
    }

    @Test func pageLeftReleasesAStoppedMeeting() async throws {
        let harness = Harness()
        let controller = await harness.stopped()
        let id = try #require(controller.meeting?.id)
        #expect(harness.coordinator.isOpen(id))

        harness.coordinator.pageLeft()

        #expect(harness.coordinator.isOpen(id) == false)
    }

    @Test(arguments: [SummaryState.writing, .rewriting(summary)])
    func pageLeftWhileItsSummaryIsWritingKeepsItFinishing(_ writing: SummaryState) async throws {
        let harness = Harness()
        let id = UUID()
        let controller = try await harness.open(id)
        let model = harness.models[0]
        controller.send(.summary(writing))
        await harness.until { model.summary == writing }

        harness.coordinator.pageLeft()

        #expect(harness.coordinator.isOpen(id))
        controller.send(.summary(.ready(Self.summary)))
        await harness.until { model.summary == .ready(Self.summary) }
        #expect(harness.coordinator.isOpen(id) == false)
    }

    @Test(arguments: [
        SummaryState.ready(summary), .failed("API error (503)."), .none("Nothing was transcribed."),
        .kept(summary, reason: "API error (503)."),
    ])
    func aFinishingSessionIsDroppedWhenItsSummaryEnds(_ end: SummaryState) async throws {
        let harness = Harness()
        let id = UUID()
        let controller = try await harness.open(id)
        let model = harness.models[0]
        controller.send(.summary(.writing))
        await harness.until { model.summary == .writing }
        harness.coordinator.pageLeft()

        controller.send(.summary(end))
        await harness.until { model.summary == end }

        #expect(harness.coordinator.isOpen(id) == false)
    }

    @Test func stopWhileShownKeepsTheSession() async throws {
        let harness = Harness()
        let controller = await harness.stopped()

        #expect(harness.coordinator.isOpen(try #require(controller.meeting?.id)))
        #expect(harness.presented.count == 1)
        #expect(harness.models[0].state == .stopped)
    }

    @Test func stopNeverPresents() async {
        let harness = Harness()
        let controller = await harness.recording()
        harness.coordinator.pageLeft()

        await harness.coordinator.toggle()
        await harness.until { harness.models[0].state == .stopped }

        #expect(controller.stops == [true])
        #expect(harness.presented.count == 1)
        #expect(harness.dismissals == 0)
    }

    @Test func stopWhileNotShownMovesTheSessionToFinishingThenDropsItOnTheSummary() async throws {
        let harness = Harness()
        let controller = await harness.recording()
        let id = try #require(controller.meeting?.id)
        let model = harness.models[0]
        harness.coordinator.pageLeft()
        let gate = Gate()
        controller.stopGate = gate
        controller.summaryOnStop = .writing

        let stopping = Task { await harness.coordinator.stop() }
        await harness.until { model.summary == .writing }

        // The page cannot show `.writing` when the stop arrives; Stop still returning keeps it.
        #expect(controller.emitted == [.state(.stopped), .summary(.writing)])
        #expect(harness.coordinator.isOpen(id))
        #expect(harness.coordinator.isActive == false)
        controller.send(.summary(.ready(Self.summary)))
        gate.open()
        await stopping.value
        await harness.until { model.summary == .ready(Self.summary) }
        #expect(harness.coordinator.isOpen(id) == false)
        #expect(harness.presented.count == 1)
    }

    @Test func stopWithoutSummaryDropsTheSessionWhenStopReturns() async throws {
        let harness = Harness()
        let controller = await harness.recording()
        let id = try #require(controller.meeting?.id)
        let model = harness.models[0]
        harness.coordinator.pageLeft()
        let gate = Gate()
        controller.stopGate = gate

        let stopping = Task { await harness.coordinator.stop(summarise: false) }
        await harness.until { model.state == .stopped }

        #expect(harness.coordinator.isOpen(id))
        gate.open()
        await stopping.value
        #expect(harness.coordinator.isOpen(id) == false)
    }

    @Test func presentingAnotherSessionReleasesThePreviouslyShownOne() async throws {
        let harness = Harness()
        let first = UUID()
        try await harness.open(first)

        let second = UUID()
        try await harness.open(second)

        #expect(harness.coordinator.isOpen(first) == false)
        #expect(harness.coordinator.isOpen(second))

        // A live meeting stays live when another page replaces it.
        let live = Harness()
        _ = await live.recording()
        try await live.open(UUID())
        #expect(live.coordinator.isActive)
        #expect(live.coordinator.liveModel === live.models[0])
    }

    @Test func isOpenCoversCurrentOpenedAndFinishing() async throws {
        let harness = Harness()
        let recording = try #require(await harness.recording().meeting?.id)
        harness.coordinator.pageLeft()
        let finishing = UUID()
        let controller = try await harness.open(finishing)
        let model = harness.models[1]
        controller.send(.summary(.writing))
        await harness.until { model.summary == .writing }
        let opened = UUID()
        try await harness.open(opened)

        #expect(harness.coordinator.isOpen(recording))
        #expect(harness.coordinator.isOpen(finishing))
        #expect(harness.coordinator.isOpen(opened))
        #expect(harness.coordinator.isOpen(UUID()) == false)
    }

    @Test func liveModelIsCurrentsWhileActive() async {
        let harness = Harness()
        #expect(harness.coordinator.liveModel == nil)
        await harness.coordinator.toggle()
        #expect(harness.coordinator.liveModel == nil)

        await harness.coordinator.start()
        #expect(harness.coordinator.liveModel === harness.models[0])

        await harness.coordinator.stop()
        #expect(harness.coordinator.liveModel == nil)
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

        await harness.until { !conductor.ends.isEmpty }
        #expect(conductor.ends == [.sleep])
    }

    @Test func testCallPageShowsTheSessionsScriptAndSkipsLines() async throws {
        let harness = Harness()
        _ = await harness.testCall()

        let pane = try #require(harness.models[0].testCall)
        #expect(pane.scenario.id == "sprint-planning")
        #expect(pane.casting[.b]?.voice == "Karen")
        harness.actions[0].skipLine()

        #expect(harness.conductorLog.calls.contains("skip"))
    }

    @Test func earlierRunsReadTheIndexAndRecordsOffTheMainActor() async throws {
        let harness = Harness()
        let meeting = try #require(await harness.testCall().meeting)
        let tag = try #require(meeting.test)
        let record = TestCallRecord(
            scenario: .init(id: tag.scenarioID, revision: tag.revision, title: tag.scenarioTitle),
            engine: .assemblyaiStreaming, overlap: true, scoredAt: Self.now, voices: [], lines: [], roles: [],
            overall: .init(words: 0, substitutions: 0, deletions: 0, insertions: 0),
            crossCredited: .init(voiceWordsAsYou: 0, yourWordsAsVoices: 0), latency: nil
        )
        harness.store.add(IndexEntry(
            id: meeting.id, title: meeting.title, startedAt: meeting.startedAt, endedAt: nil, duration: 0, mode: .remote,
            app: nil, engine: .assemblyaiStreaming, speakerCount: 0, costUSD: 0, hasSummary: false, audioBytes: 0,
            excerpt: "", test: tag
        ), record)

        await harness.models[0].loadEarlierRuns()

        #expect(harness.models[0].testCall?.runRows.map(\.isThis) == [true])
        #expect(harness.store.reads == [false])
    }

    /// The coordinator fills the chooser on its own tasks; this yields until they have.
    private func until(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
    }

    private static func entry(_ scenario: String, wer: Double?, at seconds: Double) -> IndexEntry {
        IndexEntry(
            id: UUID(), title: "Test call", startedAt: now.addingTimeInterval(seconds), endedAt: nil, duration: 0,
            mode: .remote, app: nil, engine: .assemblyaiStreaming, speakerCount: 0, costUSD: 0, hasSummary: false,
            audioBytes: 0, excerpt: "", test: TestCallTag(scenarioID: scenario, revision: 1, scenarioTitle: "", wer: wer)
        )
    }

    @Test func openChooserLoadsVoicesOnceAndScenarioWERs() async throws {
        let harness = Harness()
        harness.store.setListing("Daniel              en_GB    # Hello! My name is Daniel.\n"
            + "Karen               en_AU    # Hello! My name is Karen.\n")
        let record = TestCallRecord(
            scenario: .init(id: "sprint-planning", revision: 1, title: "Sprint planning"), engine: .assemblyaiStreaming,
            overlap: false, scoredAt: Self.now, voices: [], lines: [], roles: [],
            overall: .init(words: 0, substitutions: 0, deletions: 0, insertions: 0),
            crossCredited: .init(voiceWordsAsYou: 0, yourWordsAsVoices: 0), latency: nil
        )
        harness.store.add(Self.entry("sprint-planning", wer: 0.064, at: 0), record)
        harness.store.add(Self.entry("sprint-planning", wer: 0.2, at: -60), record)

        await harness.coordinator.toggle()
        let setup = harness.models[0].setup
        await until { setup.canOpen && !setup.scenarioOptions[0].title.hasSuffix("not run") }

        #expect(setup.canOpen)
        #expect(setup.scenarioOptions.first?.title == "Sprint planning — WER 6.4%")
        #expect(setup.scenarioOptions.last?.title == "Quarterly sales — not run · uses Karen for Laura")
        #expect(harness.store.voiceLoads == 1)
        harness.coordinator.openChooser()
        await harness.coordinator.toggle()
        #expect(harness.store.voiceLoads == 1)
        #expect(harness.store.reads.isEmpty)
    }

    @Test func setupPageStartsTheTestCall() async throws {
        let harness = Harness()
        await harness.coordinator.toggle()

        harness.actions[0].startTestCall(Self.setup())
        await until { !harness.controllers[0].starts.isEmpty }

        #expect(harness.controllers[0].starts.map(\.title) == ["Test call · Sprint planning"])
        await try #require(harness.conductors.first).started()
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
