import Testing
@testable import MiniWhisper

@MainActor
@Suite struct MainNavigationModelTests {
    private typealias Destination = MainNavigationModel.Destination

    private enum Event: Equatable {
        case meetingPageLeft
        case settingsLeft
        case entered(MainNavigationModel.Destination)
        case reveal(String)
    }

    @MainActor
    private final class Harness {
        var events: [Event] = []
        lazy var model = MainNavigationModel(hooks: MainNavigationModel.Hooks(
            meetingPageLeft: { [unowned self] in events.append(.meetingPageLeft) },
            settingsLeft: { [unowned self] in events.append(.settingsLeft) },
            entered: { [unowned self] in events.append(.entered($0)) },
            reveal: { [unowned self] in events.append(.reveal($0)) }
        ))

        /// The model at `destination`, with the hooks' record emptied.
        func at(_ destination: Destination) -> MainNavigationModel {
            switch destination {
            case .meeting: model.showMeeting()
            case .search: model.query = "rollout"
            default: model.go(destination)
            }
            events = []
            return model
        }
    }

    // MARK: - State

    @Test func startsAtMeetings() {
        let harness = Harness()
        #expect(harness.model.destination == .meetings)
        #expect(harness.model.origin == .meetings)
        #expect(harness.model.beforeSearch == .meetings)
        #expect(harness.model.query.isEmpty)
        #expect(harness.events.isEmpty)
    }

    @Test func hooksDefaultToNothing() {
        let model = MainNavigationModel()
        model.go(.settings)
        model.showMeeting()
        model.revealDictation("d1")
        #expect(model.destination == .dictations)
    }

    @Test func beforeSearchSkipsSearchAndMeeting() {
        let harness = Harness()
        let model = harness.model
        model.go(.dictations)
        #expect(model.beforeSearch == .dictations)
        model.showMeeting()
        #expect(model.beforeSearch == .dictations)
        model.query = "rollout"
        #expect(model.destination == .search)
        #expect(model.beforeSearch == .dictations)
        model.go(.settings)
        #expect(model.beforeSearch == .settings)
    }

    // MARK: - go

    @Test(arguments: [Destination.meetings, .dictations, .settings, .search])
    func goSetsTheDestinationAndReportsTheEntry(_ destination: MainNavigationModel.Destination) {
        let harness = Harness()
        harness.model.go(destination)
        #expect(harness.model.destination == destination)
        #expect(harness.events == [.entered(destination)])
    }

    /// Showing the window at the page it is already on reloads that page.
    @Test func goToTheCurrentDestinationReportsTheEntryAgain() {
        let harness = Harness()
        let model = harness.at(.settings)
        model.go(.settings)
        #expect(harness.events == [.entered(.settings)])
    }

    @Test(arguments: [Destination.meetings, .dictations, .settings])
    func goClearsTheQuery(_ destination: MainNavigationModel.Destination) {
        let harness = Harness()
        let model = harness.at(.search)
        model.go(destination)
        #expect(model.query.isEmpty)
        #expect(model.destination == destination)
        #expect(harness.events == [.entered(destination)])
    }

    @Test func goToSearchKeepsTheQuery() {
        let harness = Harness()
        let model = harness.at(.search)
        model.go(.search)
        #expect(model.query == "rollout")
        #expect(model.destination == .search)
    }

    @Test func goCallsMeetingPageLeftWhenLeavingTheMeetingPage() {
        let harness = Harness()
        let model = harness.at(.meeting)
        model.go(.dictations)
        #expect(harness.events == [.meetingPageLeft, .entered(.dictations)])
    }

    @Test func goCallsSettingsLeftWhenLeavingSettings() {
        let harness = Harness()
        let model = harness.at(.settings)
        model.go(.meetings)
        #expect(harness.events == [.settingsLeft, .entered(.meetings)])
    }

    // MARK: - showMeeting

    @Test(arguments: [Destination.meetings, .dictations, .settings])
    func showMeetingRecordsTheOrigin(_ destination: MainNavigationModel.Destination) {
        let harness = Harness()
        let model = harness.at(destination)
        model.showMeeting()
        #expect(model.destination == .meeting)
        #expect(model.origin == destination)
        #expect(harness.events == (destination == .settings ? [.settingsLeft] : []) + [.entered(.meeting)])
    }

    @Test func showMeetingFromSearchRecordsItAndKeepsTheQuery() {
        let harness = Harness()
        let model = harness.at(.search)
        model.showMeeting()
        #expect(model.destination == .meeting)
        #expect(model.origin == .search)
        #expect(model.query == "rollout")
    }

    @Test func showMeetingNeverRecordsTheMeetingPage() {
        let harness = Harness()
        let model = harness.at(.dictations)
        model.showMeeting()
        harness.events = []
        model.showMeeting()
        #expect(model.destination == .meeting)
        #expect(model.origin == .dictations)
        #expect(!harness.events.contains(.meetingPageLeft))
    }

    // MARK: - back

    @Test func backReturnsToTheOrigin() {
        let harness = Harness()
        let model = harness.at(.dictations)
        model.showMeeting()
        harness.events = []
        model.back()
        #expect(model.destination == .dictations)
        #expect(harness.events == [.meetingPageLeft, .entered(.dictations)])
    }

    @Test func backToResultsKeepsTheQuery() {
        let harness = Harness()
        let model = harness.at(.search)
        model.showMeeting()
        harness.events = []
        model.back()
        #expect(model.destination == .search)
        #expect(model.query == "rollout")
        #expect(harness.events == [.meetingPageLeft, .entered(.search)])
    }

    // MARK: - query

    @Test(arguments: [Destination.meetings, .dictations, .settings, .meeting])
    func typingAQueryGoesToSearch(_ destination: MainNavigationModel.Destination) {
        let harness = Harness()
        let model = harness.at(destination)
        model.query = "r"
        #expect(model.destination == .search)
        #expect(model.query == "r")
        let left: [Event] = switch destination {
        case .meeting: [.meetingPageLeft]
        case .settings: [.settingsLeft]
        default: []
        }
        #expect(harness.events == left + [.entered(.search)])
    }

    @Test func typingOnWhileSearchingStaysOnSearch() {
        let harness = Harness()
        let model = harness.at(.search)
        model.query = "rollout sync"
        #expect(model.destination == .search)
        #expect(harness.events.isEmpty)
    }

    @Test(arguments: [Destination.meetings, .dictations, .settings])
    func clearingTheQueryOnSearchReturnsToThePageBefore(_ destination: MainNavigationModel.Destination) {
        let harness = Harness()
        let model = harness.at(destination)
        model.query = "rollout"
        harness.events = []
        model.query = ""
        #expect(model.destination == destination)
        #expect(harness.events == [.entered(destination)])
    }

    @Test func clearingTheQueryAfterAMeetingPageReturnsToThePageBeforeIt() {
        let harness = Harness()
        let model = harness.at(.dictations)
        model.showMeeting()
        model.query = "rollout"
        model.query = ""
        #expect(model.destination == .dictations)
    }

    /// A results origin without its query has nothing to show.
    @Test func clearingTheQueryOnAMeetingOpenedFromResultsMovesTheOriginToThePageBefore() {
        let harness = Harness()
        let model = harness.at(.dictations)
        model.query = "rollout"
        model.showMeeting()
        harness.events = []
        model.query = ""
        #expect(model.destination == .meeting)
        #expect(model.origin == .dictations)
        #expect(model.backLabel == "Dictations")
        #expect(harness.events.isEmpty)
        model.back()
        #expect(model.destination == .dictations)
    }

    // MARK: - revealDictation

    @Test func revealDictationGoesToDictationsThenReveals() {
        let harness = Harness()
        let model = harness.at(.search)
        model.revealDictation("d1")
        #expect(model.destination == .dictations)
        #expect(model.query.isEmpty)
        #expect(harness.events == [.entered(.dictations), .reveal("d1")])
    }

    // MARK: - Back pill

    @Test(arguments: [
        (Destination.meetings, "Meetings"),
        (.dictations, "Dictations"),
        (.search, "Results"),
        (.settings, "Settings"),
    ])
    func backPillIsLabelledWithTheOrigin(_ origin: MainNavigationModel.Destination, _ label: String) {
        let harness = Harness()
        let model = harness.at(origin)
        model.showMeeting()
        #expect(model.backLabel == label)
    }
}
