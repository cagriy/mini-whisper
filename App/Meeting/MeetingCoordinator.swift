import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWSupport
import MWTestCall

/// What the coordinator and the meeting page need of a meeting. One conformer: `MeetingController`.
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
    func regenerateSummary() async
}

extension MeetingController: MeetingControlling {}

/// What the meeting page's buttons do.
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
    /// The chooser's engine link: Settings at its Meetings section.
    var openSettings: @MainActor () -> Void
    /// The finished page's back pill: the page it was opened from.
    var back: @MainActor () -> Void
    var copySummary: @MainActor () -> Void
    var regenerate: @MainActor () -> Void
}

/// Meeting mode's entry points (design §5.5): the hotkey and menu open a chooser, Start runs a
/// meeting from it, and a second press stops it. One `MeetingController` per session; one
/// session is on the meeting page at a time, and the others live only as long as they must.
@MainActor
final class MeetingCoordinator {
    struct Dependencies {
        /// `frontApp` is the app that was frontmost before the chooser opened.
        var makeController: @MainActor (_ frontApp: String?) -> any MeetingControlling
        var frontApp: @MainActor () -> String?
        var chooser: @MainActor () -> MeetingWindowModel.Chooser
        /// Shows the meeting page with this session and brings the window forward.
        var present: @MainActor (MeetingWindowModel, MeetingActions) -> Void
        /// Returns to the page the meeting page was opened from; leaving it calls `pageLeft()`.
        var dismiss: @MainActor () -> Void
        var now: () -> Date
        /// The models' clock, for Copy summary's `Copied`.
        var clock: any MWSupport.Clock = SystemClock()
        /// Discards a dictation still running (a toggle waits for its second press, which R19
        /// now routes to the notice), so it neither shares the microphone nor pastes mid-meeting.
        var endDictation: @MainActor () async -> Void
        var openSettings: @MainActor (SettingsModel.Section) -> Void
        /// Asks where to write the stored meeting's Markdown, then writes it (R17).
        var export: @MainActor (MeetingExporter.Kind, UUID) -> Void
        /// Puts Copy summary's three forms on the pasteboard.
        var copy: @MainActor (MeetingWindowModel.CopyPayload) -> Void
        /// A meeting changed state, title or summary: the menu, usage rows and list follow.
        var changed: @MainActor () -> Void
        var testCalls: TestCallDependencies
    }

    @MainActor
    private final class Session {
        let controller: any MeetingControlling
        let model: MeetingWindowModel
        let frontApp: String?
        var isStarting = false
        /// The coordinator's `stop()` has not returned: the summary may not have begun yet.
        var isStopping = false
        /// Set once a test call's meeting has started.
        var test: TestCallSession?

        init(controller: any MeetingControlling, model: MeetingWindowModel, frontApp: String?) {
            self.controller = controller
            self.model = model
            self.frontApp = frontApp
        }

        var state: MeetingState { controller.state }

        var isWritingSummary: Bool {
            switch model.summary {
            case .writing?, .rewriting?: true
            default: false
            }
        }
    }

    private let deps: Dependencies
    /// The chooser, or the meeting it started, until released.
    private var current: Session?
    /// A stored meeting opened from the list or search.
    private var opened: Session?
    /// Stopped sessions kept off screen while their summary is written.
    private var finishing: [Session] = []
    /// Which of `current` and `opened` is on the meeting page.
    private var shown: Session?

    init(deps: Dependencies) {
        self.deps = deps
    }

    var isActive: Bool { current?.state.isActive ?? false }

    /// The recording pill's meeting: `current` while it is active.
    var liveModel: MeetingWindowModel? {
        guard let current, current.state.isActive else { return nil }
        return current.model
    }

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

    /// *Start Meeting…* and ⌘N: the live page while a meeting is active, else the chooser.
    func openChooser() {
        if let current {
            if current.state.isActive { return show() }
            if current.state == .idle { return present(current) }
            release(current)
        }
        if let opened { release(opened) }
        // Read before the window takes focus; the default title names this app.
        let frontApp = deps.frontApp()
        let session = Session(controller: deps.makeController(frontApp), model: makeModel(), frontApp: frontApp)
        current = session
        forwardEvents(of: session)
        present(session)
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

    /// A session's model, whose test-call score reads earlier runs off the main actor (design §5.8).
    private func makeModel() -> MeetingWindowModel {
        let index = deps.testCalls.index
        let read = deps.testCalls.readRecord
        return MeetingWindowModel(chooser: deps.chooser(), now: deps.now, clock: deps.clock) { tag in
            await Task.detached {
                guard let entries = try? index() else { return [] }
                return TestRunHistory.runs(of: tag, in: entries, load: read)
            }.value
        }
    }

    /// The list's or the results' *Open*: a session already holding the meeting, or a new one
    /// once the stored meeting has loaded. A load that throws changes nothing.
    func open(_ id: UUID) async throws {
        if let session = session(holding: id) {
            if finishing.contains(where: { $0 === session }) {
                if let opened, opened !== session { release(opened) }
                finishing.removeAll { $0 === session }
                opened = session
            }
            return present(session)
        }
        let session = Session(controller: deps.makeController(nil), model: makeModel(), frontApp: nil)
        forwardEvents(of: session)
        try await session.controller.open(id)
        if let meeting = session.controller.meeting { session.model.show(meeting) }
        if let opened { release(opened) }
        if let current, current.state == .idle, !current.isStarting { drop(current) }
        opened = session
        present(session)
    }

    /// A session holds the meeting: it is recording, on the page, or its summary is being written.
    func isOpen(_ id: UUID) -> Bool {
        session(holding: id) != nil
    }

    /// The list's rename of a meeting a session holds goes through its controller, whose next
    /// save would otherwise put the old title back. False when no session holds it.
    func retitle(_ id: UUID, to title: String) async -> Bool {
        guard let session = session(holding: id) else { return false }
        if let title = session.model.commitTitle(title) { await session.controller.retitle(title) }
        return true
    }

    private func session(holding id: UUID) -> Session? {
        ([current, opened].compactMap { $0 } + finishing).first { $0.controller.meeting?.id == id }
    }

    /// *Show Meeting…* and the recording pill.
    func show() {
        guard let current, current.state.isActive else { return }
        present(current)
    }

    /// The window stopped showing the meeting page.
    func pageLeft() {
        guard let session = shown else { return }
        shown = nil
        leave(session)
    }

    /// The page's Start button.
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
    /// start; the page shows why.
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
    /// stops through its session, which scores it (design §5.5 Stop, Quit). Never presents (R4).
    func stop(summarise: Bool = true) async {
        guard let session = current, Self.isStoppable(session.state) else { return }
        session.isStopping = true
        if let test = session.test {
            await test.finish(summarise: summarise)
        } else {
            await session.controller.stop(summarise: summarise)
        }
        session.isStopping = false
        // Stopped off the page with no summary under way, as at quit.
        if finishing.contains(where: { $0 === session }), !session.isWritingSummary { drop(session) }
    }

    private static func isStoppable(_ state: MeetingState) -> Bool {
        if case .paused = state { return true }
        return state == .recording
    }

    // MARK: - Session lifetime

    /// Shows `session`; the session shown before leaves the page.
    private func present(_ session: Session) {
        if let previous = shown, previous !== session {
            shown = nil
            leave(previous)
        }
        shown = session
        deps.present(session.model, actions(for: session))
    }

    /// The page-left rule: a chooser goes unless its start is under way, a live meeting stays
    /// current, a stopped one is released.
    private func leave(_ session: Session) {
        switch session.state {
        case .idle where !session.isStarting: drop(session)
        case .stopped: release(session)
        default: break
        }
    }

    /// A stopped session leaves its slot, and is kept off screen while its summary is being
    /// written or its Stop has not returned (`.summary(.writing)` follows `.state(.stopped)`).
    private func release(_ session: Session) {
        drop(session)
        if session.isWritingSummary || session.isStopping { finishing.append(session) }
    }

    private func drop(_ session: Session) {
        if current === session { current = nil }
        if opened === session { opened = nil }
        if shown === session { shown = nil }
        finishing.removeAll { $0 === session }
    }

    private func stopped(_ session: Session) {
        if current === session, shown !== session { release(session) }
    }

    private func summaryChanged(_ session: Session) {
        if finishing.contains(where: { $0 === session }), !session.isWritingSummary { drop(session) }
    }

    private func actions(for session: Session) -> MeetingActions {
        MeetingActions(
            start: { [weak self] in Task { await self?.start() } },
            startTestCall: { [weak self] setup in Task { await self?.startTestCall(setup) } },
            cancel: deps.dismiss,
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
            openSettings: { [openSettings = deps.openSettings] in openSettings(.meetings) },
            back: deps.dismiss,
            copySummary: { [weak session, copy = deps.copy] in
                guard let model = session?.model, let payload = model.copyPayload else { return }
                copy(payload)
                model.didCopySummary()
            },
            regenerate: { [weak session] in
                guard let controller = session?.controller else { return }
                Task { await controller.regenerateSummary() }
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
                    if state == .stopped {
                        // The header's end time, duration and engine cost.
                        if let meeting = session.controller.meeting { session.model.show(meeting) }
                        self?.stopped(session)
                    }
                    self?.deps.changed()
                case .summary:
                    self?.summaryChanged(session)
                    self?.deps.changed()
                default:
                    break
                }
            }
        }
    }
}
