import Foundation
import MWConfig
import MWUsage
import Testing
@testable import MiniWhisper

@Suite struct MenuModelTests {
    private let emptyToday = "Today: 0/0 tok · 0m · $0.00"
    private let emptyMonth = "Month: $0.00"

    @Test func initialOrder() {
        let model = MenuModel()
        #expect(model.items.map(\.title) == [
            emptyToday,
            emptyMonth,
            "",
            "History...",
            "Settings...",
            "",
            "About Mini Whisper",
            "Quit",
        ])
        #expect(model.items.map(\.isSeparator) == [false, false, true, false, false, true, false, false])
        #expect(model.items.map(\.action) == [nil, nil, nil, .history, .settings, nil, .about, .quit])
    }

    @Test func lastRowInsertedAfterMonthOnFirstResult() {
        var model = MenuModel()
        model.setLast("hello")
        #expect(model.items.map(\.title) == [
            emptyToday,
            emptyMonth,
            "Last: \"hello\"",
            "",
            "History...",
            "Settings...",
            "",
            "About Mini Whisper",
            "Quit",
        ])
        #expect(model.items[2].action == .copyLast)

        model.setLast("again")
        #expect(model.items.filter { $0.action == .copyLast }.count == 1)
        #expect(model.items[2].title == "Last: \"again\"")
        #expect(model.lastText == "again")
    }

    @Test func lastRowTruncatesAt50WithEllipsis() {
        var model = MenuModel()
        let long = String(repeating: "a", count: 51)
        model.setLast(long)
        #expect(model.items[2].title == "Last: \"\(String(repeating: "a", count: 50))...\"")
        #expect(model.lastText == long)

        model.setLast(String(repeating: "b", count: 50))
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
