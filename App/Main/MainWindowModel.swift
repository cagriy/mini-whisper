import Foundation
import MWConfig
import MWStats
import MWSupport
import MWUsage
import Observation

/// The main window's state (design §5.1, §5.7): the navigation, the page models, the search,
/// the usage table and the sidebar's statistics. Navigating reloads the page it lands on; the
/// search follows the query.
@MainActor
@Observable
final class MainWindowModel {
    struct Dependencies {
        /// Opens a stored meeting from the results.
        var openMeeting: @MainActor (UUID) async throws -> Void
        /// The recording pill: the live meeting's page.
        var showLiveMeeting: @MainActor () -> Void = {}
        /// The window stopped showing the meeting page.
        var meetingPageLeft: @MainActor () -> Void = {}
        /// The meeting page was navigated to.
        var meetingEntered: @MainActor () -> Void = {}
        /// Writes the sidebar block's fold to `config.json`; the write comes back through `apply(_:)`.
        var foldStats: @MainActor (Bool) -> Void = { _ in }
        /// Computes the sidebar's figures again; they arrive in `sidebarStats`.
        var refreshStats: @MainActor () -> Void = {}
    }

    /// The session on the meeting page, as last presented.
    struct PresentedMeeting {
        let model: MeetingWindowModel
        let actions: MeetingActions
    }

    let navigation = MainNavigationModel()
    let meetings: MeetingsListModel
    let dictations: HistoryListModel
    let search: SearchModel
    let settings: SettingsModel
    let timeline: TimelineModel
    var usage = UsageTotals()
    /// The sidebar block's figures; nil until a counted meeting or a delivered dictation exists.
    var sidebarStats: SidebarStats?
    /// The block folded under its handle, leaving the usage table.
    private(set) var statsFolded = false
    /// What the meeting page shows; nil once the page is left.
    private(set) var presented: PresentedMeeting?
    /// The recording pill's meeting, while one is active.
    var liveMeeting: MeetingWindowModel?
    /// Why a meeting result did not open; cleared by the next keystroke.
    private(set) var openError: String?
    /// The page load or reveal under way.
    @ObservationIgnored private(set) var loading: Task<Void, Never>?
    private let deps: Dependencies

    init(
        meetings: MeetingsListModel,
        dictations: HistoryListModel,
        search: SearchModel,
        settings: SettingsModel,
        timeline: TimelineModel,
        deps: Dependencies
    ) {
        self.meetings = meetings
        self.dictations = dictations
        self.search = search
        self.settings = settings
        self.timeline = timeline
        self.deps = deps
        navigation.hooks.entered = { [weak self] in self?.entered($0) }
        navigation.hooks.meetingPageLeft = { [weak self] in
            self?.presented = nil
            deps.meetingPageLeft()
        }
        // R22: leaving Settings gives a hotkey capture back to the previous combo.
        navigation.hooks.settingsLeft = { [weak settings] in settings?.cancelCapture() }
        navigation.hooks.reveal = { [weak self] id in
            guard let self else { return }
            loading = Task { await self.dictations.reveal(id) }
        }
    }

    var usageTable: UsageTable { Pricing.usageTable(usage) }

    /// The sidebar's search field.
    var query: String {
        get { navigation.query }
        set {
            navigation.query = newValue
            search.query = navigation.query
            openError = nil
        }
    }

    func openMeeting(_ id: UUID) async {
        do {
            try await deps.openMeeting(id)
            openError = nil
        } catch {
            let reason = AnyError(error).description
            Log.meeting.warning("results: open failed: \(reason)")
            openError = reason
        }
    }

    func startMeeting() {
        meetings.startMeeting()
    }

    /// Shows `model` as the meeting page (design §5.5 `present`).
    func showMeeting(_ model: MeetingWindowModel, actions: MeetingActions) {
        presented = PresentedMeeting(model: model, actions: actions)
        navigation.showMeeting()
    }

    func showLiveMeeting() {
        deps.showLiveMeeting()
    }

    /// The sidebar block and its handle: hidden while Settings shows and until there is data (R25).
    var showsStats: Bool { sidebarStats != nil && navigation.destination != .settings }

    /// Flips at once; the config confirms it once written.
    func toggleStatsFold() {
        statsFolded.toggle()
        deps.foldStats(statsFolded)
    }

    /// The fold as `config.json` holds it.
    func apply(_ config: Config) {
        statsFolded = config.timelineSidebarFolded
    }

    /// The figures may have aged while the window was away (R26).
    func windowCameForward() {
        deps.refreshStats()
    }

    /// The sidebar block was clicked.
    func openTimeline() {
        navigation.go(.timeline)
    }

    /// Every navigation lands here, including one that clears the query.
    private func entered(_ destination: MainNavigationModel.Destination) {
        search.query = navigation.query
        switch destination {
        case .meetings: loading = Task { await meetings.reload() }
        case .dictations: loading = Task { await dictations.reload() }
        // A key saved or removed elsewhere changes what the engine lists offer.
        case .settings: settings.refreshKeys()
        case .meeting: deps.meetingEntered()
        // A return keeps the reader's place, year and switches, and plays nothing (R21).
        case .timeline:
            let replay = !navigation.isReturning
            loading = Task { await timeline.reload(replay: replay) }
        case .search: break
        }
    }
}
