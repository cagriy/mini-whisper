import Foundation
import MWMeetingPipeline
import MWMeetings
import MWSupport

/// What the coordinator and window need of a meeting. One conformer: `MeetingController`.
@MainActor
protocol MeetingControlling: AnyObject {
    var events: AsyncStream<MeetingEvent> { get }
    var state: MeetingState { get }
    var meeting: Meeting? { get }
    func start(mode: MeetingMode, title: String) async throws
    func stop(summarise: Bool) async
    func pause() async
    func resume() async
    func rename(speaker: Int, to name: String) async
    func addNote(_ text: String, firstKeystrokeAt time: Double) async
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
    var cancel: @MainActor () -> Void
    var pauseOrResume: @MainActor () -> Void
    var stop: @MainActor () -> Void
    var rename: @MainActor (_ speaker: Int, _ name: String) -> Void
    var addNote: @MainActor (MeetingWindowModel.DraftNote) -> Void
    var openSettings: @MainActor () -> Void
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
        var openSettings: @MainActor () -> Void
        /// A meeting changed state or got its summary: the menu and usage rows follow.
        var changed: @MainActor () -> Void
    }

    @MainActor
    private final class Session {
        let controller: any MeetingControlling
        let model: MeetingWindowModel
        let frontApp: String?
        var window: (any MeetingWindowPresenting)?
        var isStarting = false

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
        let session = Session(
            controller: deps.makeController(frontApp),
            model: MeetingWindowModel(chooser: deps.chooser()),
            frontApp: frontApp
        )
        let window = deps.makeWindow(session.model, actions(for: session))
        window.setTitle("New Meeting")
        session.window = window
        current = session
        forwardEvents(of: session)
        window.show()
    }

    /// *Show Meeting…*
    func show() {
        current?.window?.show()
    }

    /// The window's Start button.
    func start() async {
        guard let session = current, session.state == .idle, !session.isStarting, session.model.canStart
        else { return }
        session.isStarting = true
        defer { session.isStarting = false }
        let title = MeetingTitle.default(app: session.frontApp, date: deps.now())
        do {
            try await session.controller.start(mode: session.model.mode, title: title)
            if let meeting = session.controller.meeting { session.model.show(meeting) }
        } catch {
            session.model.showError(AnyError(error).description)
        }
    }

    /// `summarise: false` is the quit path; the summary can be asked for later.
    func stop(summarise: Bool = true) async {
        guard let controller = current?.controller, Self.isStoppable(controller.state) else { return }
        await controller.stop(summarise: summarise)
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
            rename: { [weak session] speaker, name in
                guard let controller = session?.controller else { return }
                Task { await controller.rename(speaker: speaker, to: name) }
            },
            addNote: { [weak session] note in
                guard let controller = session?.controller else { return }
                Task { await controller.addNote(note.text, firstKeystrokeAt: note.time) }
            },
            openSettings: deps.openSettings,
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
                    session.window?.setTitle(state == .idle ? "New Meeting" : "Meeting")
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
