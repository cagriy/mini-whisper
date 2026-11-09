import Foundation
import MWConfig
import MWPipeline
import MWUsage
import Testing
@testable import MiniWhisper

@Suite struct MenuModelTests {
    private let emptyToday = "Today: 0/0 tok · 0m · $0.00"
    private let emptyMonth = "Month: $0.00"

    private static func dictation(_ text: String) -> DeliveredDictation {
        DeliveredDictation(
            text: text,
            appName: "Slack",
            bundleID: "com.tinyspeck.slackmacgap",
            engine: .openai,
            deliveredAt: Date(timeIntervalSince1970: 1_757_088_420)
        )
    }

    @Test func initialOrder() {
        let model = MenuModel()
        #expect(model.items.map(\.title) == [
            emptyToday,
            emptyMonth,
            "",
            "Start Meeting…",
            "Meetings…",
            "History...",
            "Settings...",
            "",
            "Check for Updates…",
            "About Mini Whisper",
            "Quit",
        ])
        #expect(model.items.map(\.isSeparator) == [false, false, true, false, false, false, false, true, false, false, false])
        #expect(model.items.map(\.action) == [
            nil, nil, nil, .startMeeting, .meetings, .history, .settings, nil, .checkForUpdates, .about, .quit,
        ])
    }

    @Test func activeMeetingShowsStopAndShowMeeting() {
        var model = MenuModel()
        model.setMeetingActive(true)
        #expect(model.items.map(\.title)[2...6] == ["", "Stop Meeting", "Show Meeting…", "Meetings…", "History..."])
        #expect(model.items.map(\.action)[3...4] == [.stopMeeting, .showMeeting])
        #expect(!model.items.contains { $0.action == .startMeeting })
    }

    @Test func endingTheMeetingRestoresStartMeeting() {
        var model = MenuModel()
        model.setMeetingActive(true)
        model.setMeetingActive(false)
        #expect(model.items == MenuModel().items)
        model.setMeetingActive(false)
        #expect(model.items == MenuModel().items)
    }

    @Test func meetingsRowIsAlwaysPresent() {
        var model = MenuModel()
        for active in [true, false, true] {
            model.setMeetingActive(active)
            let titles = model.items.map(\.title)
            let meetings = titles.firstIndex(of: "Meetings…")
            #expect(model.items.filter { $0.action == .meetings }.count == 1)
            #expect(meetings.map { titles[$0 + 1] } == "History...")
            #expect(meetings.map { titles[$0 - 1] } == (active ? "Show Meeting…" : "Start Meeting…"))
        }
    }

    @Test func lastAndCorrectRowsStillFollowMonth() {
        var model = MenuModel()
        model.setMeetingActive(true)
        model.setLast(Self.dictation("hello"))
        #expect(model.items.map(\.title)[1...6] == [
            emptyMonth, "Last: \"hello\"", "Correct Last Dictation…", "", "Stop Meeting", "Show Meeting…",
        ])
        model.setMeetingActive(false)
        #expect(model.items.map(\.title)[2...7] == [
            "Last: \"hello\"", "Correct Last Dictation…", "", "Start Meeting…", "Meetings…", "History...",
        ])
    }

    /// R27: both rows are absent until a dictation has been delivered.
    @Test func lastAndCorrectRowsInsertedAfterMonthOnFirstResult() {
        var model = MenuModel()
        model.setLast(Self.dictation("hello"))
        #expect(model.items.map(\.title) == [
            emptyToday,
            emptyMonth,
            "Last: \"hello\"",
            "Correct Last Dictation…",
            "",
            "Start Meeting…",
            "Meetings…",
            "History...",
            "Settings...",
            "",
            "Check for Updates…",
            "About Mini Whisper",
            "Quit",
        ])
        #expect(model.items[2].action == .copyLast)
        #expect(model.items[3].action == .correctLast)

        model.setLast(Self.dictation("again"))
        #expect(model.items.filter { $0.action == .copyLast }.count == 1)
        #expect(model.items.filter { $0.action == .correctLast }.count == 1)
        #expect(model.items[2].title == "Last: \"again\"")
        #expect(model.lastText == "again")
        #expect(model.lastDictation == Self.dictation("again"))
    }

    @Test func lastRowTruncatesAt50WithEllipsis() {
        var model = MenuModel()
        let long = String(repeating: "a", count: 51)
        model.setLast(Self.dictation(long))
        #expect(model.items[2].title == "Last: \"\(String(repeating: "a", count: 50))...\"")
        #expect(model.lastText == long)

        model.setLast(Self.dictation(String(repeating: "b", count: 50)))
        #expect(model.items[2].title == "Last: \"\(String(repeating: "b", count: 50))\"")
    }

    @Test func usageRowsUseFormatUsageRows() {
        var model = MenuModel()
        let today = DayUsage(
            inputTokens: 1234,
            outputTokens: 340,
            streamedSeconds: ["on_device": 200],
            costUSD: 0.12
        )
        model.setUsage(today: today, monthCost: 1.5)
        let expected = Pricing.formatUsageRows(today: today, monthCost: 1.5)
        #expect(model.items[0].title == expected.today)
        #expect(model.items[1].title == expected.month)

        model.setUsage(today: "Today: x", month: "Month: y")
        #expect(model.items[0].title == "Today: x")
        #expect(model.items[1].title == "Month: y")
    }
}
