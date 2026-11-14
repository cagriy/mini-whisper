import Foundation
import MWSupport
import MWUsage
import Observation

/// The main window's state (design §5.1, §5.7): the navigation, the page models, the search
/// and the usage table. Navigating reloads the page it lands on; the search follows the query.
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
    var usage = UsageTotals()
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
        deps: Dependencies
    ) {
        self.meetings = meetings
        self.dictations = dictations
        self.search = search
        self.settings = settings
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

    /// Every navigation lands here, including one that clears the query.
    private func entered(_ destination: MainNavigationModel.Destination) {
        search.query = navigation.query
        switch destination {
        case .meetings: loading = Task { await meetings.reload() }
        case .dictations: loading = Task { await dictations.reload() }
        // A key saved or removed elsewhere changes what the engine lists offer.
        case .settings: settings.refreshKeys()
        case .search, .meeting: break
        }
    }
}
