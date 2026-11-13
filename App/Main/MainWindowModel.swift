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
        /// Settings is still its own window.
        var openSettings: @MainActor () -> Void
    }

    let navigation = MainNavigationModel()
    let meetings: MeetingsListModel
    let dictations: HistoryListModel
    let search: SearchModel
    var usage = UsageTotals()
    /// Why a meeting result did not open; cleared by the next keystroke.
    private(set) var openError: String?
    /// The page load or reveal under way.
    @ObservationIgnored private(set) var loading: Task<Void, Never>?
    private let deps: Dependencies

    init(meetings: MeetingsListModel, dictations: HistoryListModel, search: SearchModel, deps: Dependencies) {
        self.meetings = meetings
        self.dictations = dictations
        self.search = search
        self.deps = deps
        navigation.hooks.entered = { [weak self] in self?.entered($0) }
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

    func openSettings() {
        deps.openSettings()
    }

    /// Every navigation lands here, including one that clears the query.
    private func entered(_ destination: MainNavigationModel.Destination) {
        search.query = navigation.query
        switch destination {
        case .meetings: loading = Task { await meetings.reload() }
        case .dictations: loading = Task { await dictations.reload() }
        case .settings, .search, .meeting: break
        }
    }
}
