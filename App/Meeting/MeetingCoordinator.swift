import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWSupport
import MWTestCall

/// What the coordinator and window need of a meeting. One conformer: `MeetingController`.
@MainActor
protocol MeetingControlling: AnyObject {
    var events: AsyncStream<MeetingEvent> { get }
    var state: MeetingState { get }
    var meeting: Meeting? { get }
    var meetingTime: Double { get }
    var userSpeech: SpeechGate.View { get }
    var lastAudibleSystemAudio: Double? { get }
    func start(mode: MeetingMode, title: String, engine: MeetingEngine?, test: TestCallTag?) async throws
    func stop(summarise: Bool) async
    func finishTest(_ run: TestCallRun, scenario: TestScenario) async
    func pause() async
    func resume() async
    func rename(speaker: Int, to name: String) async
    func addNote(_ text: String, firstKeystrokeAt time: Double) async
    func open(_ id: UUID) async throws
    func summarise() async
    func edit(segment: UUID, text: String) async
    func reassign(segment: UUID, to speaker: Int) async
    func retitle(_ title: String) async
}

extension MeetingController: MeetingControlling {}

/// The meeting window as the coordinator drives it. One conformer: `MeetingWindowController`.
@MainActor
protocol MeetingWindowPresenting: AnyObject {
    var isVisible: Bool { get }
    func show()
    func close()
    func setTitle(_ title: String)
}

/// What the meeting window's buttons do.
struct MeetingActions {
    var start: @MainActor () -> Void
    /// The setup page's Start Test Call.
    var startTestCall: @MainActor (TestCallSetup) -> Void
    var cancel: @MainActor () -> Void
    var pauseOrResume: @MainActor () -> Void
    var stop: @MainActor () -> Void
    /// A test call's Skip line.
    var skipLine: @MainActor () -> Void
    var rename: @MainActor (_ speaker: Int, _ name: String) -> Void
    var addNote: @MainActor (MeetingWindowModel.DraftNote) -> Void
    var summarise: @MainActor () -> Void
    var edit: @MainActor (_ segment: UUID, _ text: String) -> Void
    var reassign: @MainActor (_ segment: UUID, _ speaker: Int) -> Void
    /// The header's title field, as typed.
    var retitle: @MainActor (_ draft: String) -> Void
    var export: @MainActor (MeetingExporter.Kind) -> Void
    var openSettings: @MainActor () -> Void
    /// A stopped meeting's *Meetings* button: this window closes and the list comes up.
    var backToMeetings: @MainActor () -> Void
    /// The window was closed: a chooser or an ended meeting goes away, a live one only hides.
    var closed: @MainActor () -> Void
}

/// Meeting mode's entry points (design §5.6 Start, Second hotkey press; §5.7 window closed,
/// quit): the hotkey and menu open a chooser, Start runs a meeting in that window, and a second
/// press stops it. One `MeetingController` per window.
@MainActor
final class MeetingCoordinator {
    struct Dependencies {
        /// `frontApp` is the app that was frontmost before the chooser opened.
        var makeController: @MainActor (_ frontApp: String?) -> any MeetingControlling
        var frontApp: @MainActor () -> String?
        var chooser: @MainActor () -> MeetingWindowModel.Chooser
        var makeWindow: @MainActor (MeetingWindowModel, MeetingActions) -> any MeetingWindowPresenting
        var now: () -> Date
        /// Discards a dictation still running (a toggle waits for its second press, which R19
        /// now routes to the notice), so it neither shares the microphone nor pastes mid-meeting.
        var endDictation: @MainActor () async -> Void
        var openSettings: @MainActor () -> Void
        var openMeetings: @MainActor () -> Void
        /// Asks where to write the stored meeting's Markdown, then writes it (R17).
        var export: @MainActor (MeetingExporter.Kind, UUID) -> Void
        /// A meeting changed state, title or summary: the menu, usage rows and list follow.
        var changed: @MainActor () -> Void
        var testCalls: TestCallDependencies
    }

    @MainActor
    private final class Session {
        let controller: any MeetingControlling
        let model: MeetingWindowModel
        let frontApp: String?
        var window: (any MeetingWindowPresenting)?
        var isStarting = false
        /// Set once a test call's meeting has started.
        var test: TestCallSession?

        init(controller: any MeetingControlling, model: MeetingWindowModel, frontApp: String?) {
            self.controller = controller
            self.model = model
            self.frontApp = frontApp
        }

        var state: MeetingState { controller.state }
    }

    private let deps: Dependencies
    /// The chooser, or the meeting it started.
    private var current: Session?
    /// Ended meetings whose windows are still open.
    private var ended: [Session] = []

    init(deps: Dependencies) {
        self.deps = deps
    }

    var isActive: Bool { current?.state.isActive ?? false }

    /// Recording or paused: the states Stop acts on (§5.7 Quit while recording).
    var needsQuitConfirmation: Bool {
        guard let state = current?.state else { return false }
        return Self.isStoppable(state)
    }

    /// The meeting hotkey: a chooser when no meeting is active, Stop while one records or is
    /// paused, nothing while the chooser is open or a start or stop is under way (R1).
    func toggle() async {
        switch current?.state {
        case nil, .stopped?: openChooser()
        case .recording?, .paused?: await stop()
        case .idle?, .starting?, .stopping?: break
        }
    }

    /// *Start Meeting…*: like the hotkey, but an open chooser comes to the front.
    func openChooser() {
        if let current {
            switch current.state {
            case .idle:
                current.window?.show()
                return
            case .stopped: end(current)
            case .starting, .recording, .paused, .stopping: return
            }
        }
        // Read before the window takes focus; the default title names this app.
        let frontApp = deps.frontApp()
        let session = Session(controller: deps.makeController(frontApp), model: makeModel(), frontApp: frontApp)
        current = session
        forwardEvents(of: session)
        present(session, title: "New Meeting")
        fillTestCallSetup(session.model.setup)
    }

    /// Design §5.5 step 1: this Mac's voices and each scenario's latest WER, read off the main
    /// actor once per chooser.
    private func fillTestCallSetup(_ setup: TestCallSetupModel) {
        let loadVoices = deps.testCalls.loadVoices
        let index = deps.testCalls.index
        let revisions = Dictionary(uniqueKeysWithValues: ScenarioLibrary.all.map { ($0.id, $0.revision) })
        Task { [weak setup] in
            let listing = await loadVoices()
            let wer = await Task.detached {
                TestRunHistory.latestWER(in: (try? index()) ?? [], revisions: revisions)
            }.value
            setup?.showVoices(VoiceCatalog.parse(listing))
            setup?.showLatestWER(wer)
        }
    }

    /// A window's model, whose test-call score reads earlier runs off the main actor (design §5.8).
    private func makeModel() -> MeetingWindowModel {
        let index = deps.testCalls.index
        let read = deps.testCalls.readRecord
        return MeetingWindowModel(chooser: deps.chooser(), now: deps.now) { tag in
            await Task.detached {
                guard let entries = try? index() else { return [] }
                return TestRunHistory.runs(of: tag, in: entries, load: read)
            }.value
        }
    }

    private func present(_ session: Session, title: String) {
        let window = deps.makeWindow(session.model, actions(for: session))
        window.setTitle(title)
        session.window = window
        window.show()
    }

    /// The list's *Open*: a stored meeting in its own window, stopped (§5.3). Its window
    /// appears once the controller's events have filled it; an open one comes to the front.
    func open(_ id: UUID) async throws {
        if let session = session(showing: id) {
            session.window?.show()
            return
        }
        let session = Session(controller: deps.makeController(nil), model: makeModel(), frontApp: nil)
        forwardEvents(of: session)
        try await session.controller.open(id)
        if let meeting = session.controller.meeting { session.model.show(meeting) }
        ended.append(session)
    }

    /// The meeting has a window: the chooser's, a live one or an ended one still open.
    func isOpen(_ id: UUID) -> Bool {
        session(showing: id) != nil
    }

    /// The list's rename of a meeting with a window goes through its controller, whose next
    /// save would otherwise put the old title back. False when no window shows it.
    func retitle(_ id: UUID, to title: String) async -> Bool {
        guard let session = session(showing: id) else { return false }
        if let title = session.model.commitTitle(title) { await session.controller.retitle(title) }
        return true
    }

    private func session(showing id: UUID) -> Session? {
        ([current].compactMap { $0 } + ended).first { $0.controller.meeting?.id == id }
    }

    /// *Show Meeting…*
    func show() {
        current?.window?.show()
    }

    /// The window's Start button.
    func start() async {
        guard let session = current, session.model.canStart else { return }
        let title = MeetingTitle.default(app: session.frontApp, date: deps.now())
        await begin(session) { try await $0.start(mode: session.model.mode, title: title, engine: nil, test: nil) }
    }

    /// The setup page's Start Test Call (design §5.5 steps 2–3): a remote meeting on the chosen
    /// engine, tagged with the scenario, whose script plays once it records.
    func startTestCall(_ setup: TestCallSetup) async {
        guard let session = current, session.state == .idle, !session.isStarting else { return }
        var random = SystemRandomNumberGenerator()
        let scenario = ScenarioLibrary.pick(setup.choice, using: &random)
        guard case .ready(let casting) = VoiceCatalog(voices: setup.voices).cast(scenario) else {
            return session.model.showError(TestCallSetup.voicesUnavailable)
        }
        let tag = TestCallTag(scenarioID: scenario.id, revision: scenario.revision, scenarioTitle: scenario.title)
        let started = await begin(session) {
            try await $0.start(mode: .remote, title: "Test call · \(scenario.title)", engine: setup.engine, test: tag)
        }
        guard started else { return }
        let test = TestCallSession(
            controller: session.controller, scenario: scenario, casting: casting, engine: setup.engine,
            overlap: setup.overlap, deps: deps.testCalls
        )
        session.test = test
        session.model.attach(test.pane)
        test.start()
    }

    /// Starts `session`'s meeting once, after any dictation has ended. False when it did not
    /// start; the window shows why.
    @discardableResult
    private func begin(
        _ session: Session, _ start: @MainActor (any MeetingControlling) async throws -> Void
    ) async -> Bool {
        guard session.state == .idle, !session.isStarting else { return false }
        session.isStarting = true
        defer { session.isStarting = false }
        await deps.endDictation()
        do {
            try await start(session.controller)
        } catch {
            session.model.showError(AnyError(error).description)
            return false
        }
        if let meeting = session.controller.meeting { session.model.show(meeting) }
        return true
    }

    /// `summarise: false` is the quit path; the summary can be asked for later. A test call
    /// stops through its session, which scores it (design §5.5 Stop, Quit).
    func stop(summarise: Bool = true) async {
        guard let session = current, Self.isStoppable(session.state) else { return }
        if let test = session.test {
            await test.finish(summarise: summarise)
        } else {
            await session.controller.stop(summarise: summarise)
        }
    }

    private static func isStoppable(_ state: MeetingState) -> Bool {
        if case .paused = state { return true }
        return state == .recording
    }

    /// An ended meeting keeps its window until the user closes it.
    private func end(_ session: Session) {
        if session.window?.isVisible == true { ended.append(session) }
        if current === session { current = nil }
    }

    private func closed(_ session: Session) {
        guard !session.state.isActive, !session.isStarting else { return }
        if current === session { current = nil }
        ended.removeAll { $0 === session }
    }

    private func actions(for session: Session) -> MeetingActions {
        MeetingActions(
            start: { [weak self] in Task { await self?.start() } },
            startTestCall: { [weak self] setup in Task { await self?.startTestCall(setup) } },
            cancel: { [weak session] in session?.window?.close() },
            pauseOrResume: { [weak session] in
                guard let controller = session?.controller else { return }
                Task {
                    if case .paused = controller.state {
                        await controller.resume()
                    } else {
                        await controller.pause()
                    }
                }
            },
            stop: { [weak self] in Task { await self?.stop() } },
            skipLine: { [weak session] in session?.test?.skip() },
            rename: { [weak session] speaker, name in
                guard let controller = session?.controller else { return }
                Task { await controller.rename(speaker: speaker, to: name) }
            },
            addNote: { [weak session] note in
                guard let controller = session?.controller else { return }
                Task { await controller.addNote(note.text, firstKeystrokeAt: note.time) }
            },
            summarise: { [weak session] in
                guard let controller = session?.controller else { return }
                Task { await controller.summarise() }
            },
            edit: { [weak session] segment, text in
                guard let controller = session?.controller else { return }
                Task { await controller.edit(segment: segment, text: text) }
            },
            reassign: { [weak session] segment, speaker in
                guard let controller = session?.controller else { return }
                Task { await controller.reassign(segment: segment, to: speaker) }
            },
            retitle: { [weak self, weak session] draft in
                guard let session, let title = session.model.commitTitle(draft) else { return }
                Task {
                    await session.controller.retitle(title)
                    self?.deps.changed()
                }
            },
            export: { [weak self, weak session] kind in
                guard let id = session?.controller.meeting?.id else { return }
                self?.deps.export(kind, id)
            },
            openSettings: deps.openSettings,
            // Closed first: closing makes the app an accessory, and the list makes it regular again.
            backToMeetings: { [weak session, openMeetings = deps.openMeetings] in
                session?.window?.close()
                openMeetings()
            },
            closed: { [weak self, weak session] in
                guard let session else { return }
                self?.closed(session)
            }
        )
    }

    /// The controller's events finish when it is released, which ends this task.
    private func forwardEvents(of session: Session) {
        let events = session.controller.events
        Task { [weak self, weak session] in
            for await event in events {
                guard let session else { return }
                session.model.apply(event)
                switch event {
                case .state(let state):
                    if state == .paused(.sleep) { session.test?.macSlept() }
                    // The header's end time, duration and engine cost.
                    if state == .stopped, let meeting = session.controller.meeting { session.model.show(meeting) }
                    if session.window == nil {
                        self?.present(session, title: "Meeting")
                    } else {
                        session.window?.setTitle(state == .idle ? "New Meeting" : "Meeting")
                    }
                    self?.deps.changed()
                case .summary:
                    self?.deps.changed()
                default:
                    break
                }
            }
        }
    }
}
