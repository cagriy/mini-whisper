import MWConfig
import MWPipeline
import MWUsage

/// One row of the status-bar menu (F31). Pure data so the order and the row
/// formats are host-testable without an `NSMenu`.
struct MenuItem: Equatable {
    enum Action: Equatable {
        case copyLast
        case correctLast
        case startMeeting
        case stopMeeting
        case showMeeting
        case meetings
        case history
        case settings
        case checkForUpdates
        case about
        case quit
    }

    var title: String
    /// `nil` for rows that do nothing when clicked (the two usage rows and separators).
    var action: Action?
    var isSeparator = false

    static let separator = MenuItem(title: "", action: nil, isSeparator: true)
}

/// The menu's contents in F31 order. `Last:` and `Correct Last Dictation…` are absent
/// until the first delivered dictation and are then kept immediately after `Month:`.
struct MenuModel {
    private(set) var items: [MenuItem]
    /// The last delivered dictation, which the correction window works from (R27).
    private(set) var lastDictation: DeliveredDictation?
    /// The untruncated text the `Last:` row copies.
    var lastText: String { lastDictation?.text ?? "" }

    private static let maxLastLength = 50

    init() {
        let rows = Pricing.formatUsageRows(today: DayUsage(), monthCost: 0)
        items = [
            MenuItem(title: rows.today, action: nil),
            MenuItem(title: rows.month, action: nil),
            .separator,
            MenuItem(title: "Start Meeting…", action: .startMeeting),
            MenuItem(title: "Meetings…", action: .meetings),
            MenuItem(title: "History...", action: .history),
            MenuItem(title: "Settings...", action: .settings),
            .separator,
            MenuItem(title: "Check for Updates…", action: .checkForUpdates),
            MenuItem(title: "About Mini Whisper", action: .about),
            MenuItem(title: "Quit", action: .quit),
        ]
    }

    /// R1: *Stop Meeting* and *Show Meeting…* replace *Start Meeting…* while a meeting
    /// records or is paused; *Meetings…* stays.
    mutating func setMeetingActive(_ active: Bool) {
        let meetingActions: [MenuItem.Action] = [.startMeeting, .stopMeeting, .showMeeting]
        items.removeAll { $0.action.map(meetingActions.contains) ?? false }
        let rows = active
            ? [MenuItem(title: "Stop Meeting", action: .stopMeeting), MenuItem(title: "Show Meeting…", action: .showMeeting)]
            : [MenuItem(title: "Start Meeting…", action: .startMeeting)]
        items.insert(contentsOf: rows, at: items.firstIndex { $0.action == .meetings } ?? items.endIndex)
    }

    mutating func setUsage(today: String, month: String) {
        items[0].title = today
        items[1].title = month
    }

    mutating func setUsage(today: DayEntry, monthCost: Double) {
        let rows = Pricing.formatUsageRows(today: today, monthCost: monthCost)
        setUsage(today: rows.today, month: rows.month)
    }

    mutating func setLast(_ dictation: DeliveredDictation) {
        lastDictation = dictation
        let title = "Last: \"\(Self.truncated(dictation.text))\""
        if let index = items.firstIndex(where: { $0.action == .copyLast }) {
            items[index].title = title
        } else {
            // R27: the two rows arrive together with the first delivered dictation.
            items.insert(
                contentsOf: [
                    MenuItem(title: title, action: .copyLast),
                    MenuItem(title: "Correct Last Dictation…", action: .correctLast),
                ],
                at: 2
            )
        }
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > maxLastLength else { return text }
        return text.prefix(maxLastLength) + "..."
    }
}
