import Observation

/// Which page the main window shows and where it returns to (design §5.7). The pages'
/// side effects arrive as hooks, so the rules are tested without a window.
@MainActor
@Observable
final class MainNavigationModel {
    enum Destination: Hashable { case meetings, dictations, settings, search, meeting }

    struct Hooks {
        /// The destination stopped being the meeting page.
        var meetingPageLeft: @MainActor () -> Void = {}
        /// The destination stopped being Settings.
        var settingsLeft: @MainActor () -> Void = {}
        /// A destination was navigated to, the current one included: its page reloads.
        var entered: @MainActor (Destination) -> Void = { _ in }
        /// Selects a dictation, once Dictations is the destination.
        var reveal: @MainActor (String) -> Void = { _ in }
    }

    @ObservationIgnored var hooks: Hooks
    private(set) var destination = Destination.meetings
    /// Where `back()` goes from the meeting page; never `.meeting`.
    private(set) var origin = Destination.meetings
    /// The last destination that was neither `.search` nor `.meeting`.
    private(set) var beforeSearch = Destination.meetings

    /// The search text. Typing shows the results; clearing it returns to the page before.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            if !query.isEmpty {
                if destination != .search { change(to: .search, clearingQuery: false) }
            } else if destination == .search {
                go(beforeSearch)
            } else if destination == .meeting, origin == .search {
                // Results without a query are no page to go back to.
                origin = beforeSearch
            }
        }
    }

    init(hooks: Hooks = Hooks()) {
        self.hooks = hooks
    }

    /// The back pill's text on a meeting page.
    var backLabel: String {
        switch origin {
        case .meetings, .meeting: "Meetings"
        case .dictations: "Dictations"
        case .search: "Results"
        case .settings: "Settings"
        }
    }

    func go(_ destination: Destination) {
        change(to: destination, clearingQuery: destination != .search)
    }

    /// Shows the meeting page, remembering the page it was opened from. A results origin
    /// keeps its query.
    func showMeeting() {
        if destination != .meeting { origin = destination }
        change(to: .meeting, clearingQuery: false)
    }

    func back() {
        go(origin)
    }

    func revealDictation(_ id: String) {
        go(.dictations)
        hooks.reveal(id)
    }

    /// State first, hooks after, so a hook reads the page it was called for.
    private func change(to next: Destination, clearingQuery: Bool) {
        let previous = destination
        destination = next
        if next != .search, next != .meeting { beforeSearch = next }
        if clearingQuery { query = "" }
        if previous != next {
            if previous == .meeting { hooks.meetingPageLeft() }
            if previous == .settings { hooks.settingsLeft() }
        }
        hooks.entered(next)
    }
}
