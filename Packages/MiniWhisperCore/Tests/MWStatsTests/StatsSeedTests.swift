import Foundation
import MWConfig
import MWHistory
import MWMeetings
import MWTestSupport
import Testing

import MWStats

@Suite struct StatsSeedTests {
    private static let mail = "com.example.mail"

    /// Berlin moves to +01:00 on 25 October 2026, so October and November days carry different
    /// offsets and a local day differs from its UTC day around midnight.
    private static let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ text: String) throws -> Date {
        try #require(StatsTime.parse(text)).date
    }

    private func seed(
        history: [HistoryEntry] = [], usage: [String: DayUsage] = [:], meetings: [Meeting] = [],
        now: String = "2026-11-20T10:00:00+01:00"
    ) throws -> StatsSeed {
        StatsSeed(history: history, usage: usage, meetings: meetings, now: try date(now), calendar: Self.berlin)
    }

    private func entry(
        _ id: String, at: String, text: String = "Ship the release notes today",
        bundleID: String? = StatsSeedTests.mail, engine: String? = "speech_analyzer", seconds: Double = 0,
        cost: Double = 0
    ) throws -> HistoryEntry {
        HistoryEntry(
            id: id, timestamp: try date(at), text: text, appName: "Mail", bundleID: bundleID, engine: engine,
            streamedSeconds: seconds, costUSD: cost
        )
    }

    private func meeting(
        started: String, ended: String?, engine: MeetingEngine = .speechmaticsStandard,
        billing: Billing = Billing(), summary: Summary? = nil, test: TestCallTag? = nil
    ) throws -> Meeting {
        Meeting(
            title: "Budget review", startedAt: try date(started), endedAt: try ended.map { try date($0) },
            mode: .remote, engine: engine, userName: "Alex", summary: summary, billing: billing, test: test
        )
    }

    private func summary(cost: Double, tokensIn: Int = 0, tokensOut: Int = 0) -> Summary {
        Summary(
            text: "## Budget", model: "claude-sonnet-5-5", createdAt: Date(timeIntervalSince1970: 0),
            inputTokens: tokensIn, outputTokens: tokensOut, costUSD: cost
        )
    }

    private static let testCall = TestCallTag(scenarioID: "standup", revision: 1, scenarioTitle: "Standup")

    private func totalUSD(_ seed: StatsSeed) -> Double {
        seed.days.reduce(0) { sum, day in day.spend.keys.sorted().reduce(sum) { $0 + day.spend[$1]!.usd } }
    }

    // MARK: - Step 1: history

    @Test func eachHistoryEntryBecomesASeededDeliveredRowOldestFirst() throws {
        let later = try entry(
            "h2", at: "2026-11-03T09:15:00+01:00", text: "Ship the release notes today", seconds: 4.5, cost: 0.002
        )
        let earlier = try entry(
            "h1", at: "2026-11-02T17:40:12+00:00", text: "Book the room", bundleID: nil, engine: nil, cost: 0.001
        )

        let seed = try seed(history: [later, earlier])

        #expect(seed.dictations == [
            DictationRow(
                id: "h1", at: "2026-11-02T18:40:12+01:00", words: 3, outcome: .delivered, usd: 0.001, seeded: true
            ),
            DictationRow(
                id: "h2", at: "2026-11-03T09:15:00+01:00", app: Self.mail, engine: "speech_analyzer", seconds: 4.5,
                words: 5, outcome: .delivered, usd: 0.002, seeded: true
            ),
        ])
    }

    @Test func aHistoryDayLineCountsDeliveredWordsAppsAndHoursWithSecondsOnlyWhenStreamed() throws {
        let seed = try seed(history: [
            entry("a", at: "2026-11-03T09:15:00+01:00", seconds: 4.5, cost: 0.002),
            entry("b", at: "2026-11-03T09:50:00+01:00", text: "Book the room", bundleID: nil, cost: 0.001),
            entry("c", at: "2026-11-03T16:05:00+00:00", text: "Yes", seconds: 2, cost: 0.001),
        ])

        #expect(seed.days == [DayRow(
            day: "2026-11-03", delivered: 3, words: 9, seconds: 6.5, timedWords: 6,
            apps: [Self.mail: 2, "other": 1], hours: ["9": 2, "17": 1]
        )])
    }

    @Test func dictationSpendAppearsOnlyForDaysBeforeMonthStart() throws {
        let seed = try seed(history: [
            entry("batch", at: "2026-10-10T08:00:00+00:00", engine: nil, cost: 0.004),
            entry("before", at: "2026-10-31T22:30:00+00:00", seconds: 4, cost: 0.003),
            entry("after", at: "2026-10-31T23:30:00+00:00", seconds: 4, cost: 0.003),
        ])

        #expect(seed.days.map(\.day) == ["2026-10-10", "2026-10-31", "2026-11-01"])
        #expect(seed.days.map(\.hours) == [["10": 1], ["23": 1], ["0": 1]])
        #expect(seed.days.map(\.spend) == [
            ["dictation": Spend(usd: 0.004)],
            ["dictation": Spend(usd: 0.003, seconds: ["speech_analyzer": 4])],
            [:],
        ])
    }

    // MARK: - Step 2: this month's usage

    @Test func eachCurrentMonthUsageDayBecomesUnsplitSpend() throws {
        let usage = DayUsage(
            inputTokens: 1_200, outputTokens: 300, streamedSeconds: ["speechmatics": 600, "speech_analyzer": 30],
            costUSD: 0.5
        )

        let seed = try seed(usage: ["2026-11-03": usage])

        #expect(seed.days == [DayRow(day: "2026-11-03", spend: ["unsplit": Spend(
            usd: 0.5, tokensIn: 1_200, tokensOut: 300, seconds: ["speechmatics": 600, "speech_analyzer": 30]
        )])])
    }

    @Test func unsplitLeavesOutKeptTestCallsThatEndedThatDayFlooredAtZero() throws {
        let usage = [
            "2026-11-03": DayUsage(
                inputTokens: 1_200, outputTokens: 300, streamedSeconds: ["speechmatics": 600, "speech_analyzer": 30],
                costUSD: 0.5
            ),
            "2026-11-04": DayUsage(inputTokens: 40, streamedSeconds: ["assemblyai": 60], costUSD: 0.05),
        ]
        let meetings = [
            try meeting(
                started: "2026-11-03T13:50:00+01:00", ended: "2026-11-03T14:00:00+01:00",
                billing: Billing(engineSeconds: 120, costUSD: 0.1), summary: summary(cost: 0.05), test: Self.testCall
            ),
            try meeting(
                started: "2026-11-03T23:55:00+01:00", ended: "2026-11-04T00:05:00+01:00", engine: .assemblyaiStreaming,
                billing: Billing(engineSeconds: 300, costUSD: 0.2), test: Self.testCall
            ),
            try meeting(
                started: "2026-11-03T15:00:00+01:00", ended: nil, billing: Billing(engineSeconds: 60, costUSD: 0.3),
                test: Self.testCall
            ),
            try meeting(
                started: "2026-11-03T16:00:00+01:00", ended: "2026-11-03T17:00:00+01:00",
                billing: Billing(engineSeconds: 3_600, costUSD: 0.2)
            ),
        ]

        let seed = try seed(usage: usage, meetings: meetings)

        #expect(seed.days.map(\.day) == ["2026-11-03", "2026-11-04"])
        let third = try #require(seed.days.first?.spend["unsplit"])
        #expect(abs(third.usd - 0.35) < 1e-9)
        #expect(third.tokensIn == 1_200)
        #expect(third.tokensOut == 300)
        #expect(third.seconds == ["speechmatics": 480, "speech_analyzer": 30])
        #expect(seed.days.last?.spend == ["unsplit": Spend(tokensIn: 40)])
    }

    @Test func usageDaysOutsideTheMonthAreIgnored() throws {
        let seed = try seed(usage: [
            "2026-10-31": DayUsage(costUSD: 0.5),
            "2026-11-20": DayUsage(costUSD: 0.125),
            "2026-12-01": DayUsage(costUSD: 0.25),
        ])

        #expect(seed.days == [DayRow(day: "2026-11-20", spend: ["unsplit": Spend(usd: 0.125)])])
    }

    // MARK: - Step 3: earlier months' meetings

    @Test func keptMeetingsStartedBeforeMonthStartAddMeetingSummaryAndNamingSpend() throws {
        let billing = Billing(
            engineSeconds: 3_600, costUSD: 0.375, replacedSummaryCostUSD: 0.03125, namingCostUSD: 0.015625
        )
        let kept = try meeting(
            started: "2026-10-12T22:30:00+00:00", ended: "2026-10-12T23:30:00+00:00", engine: .speechmaticsEnhanced,
            billing: billing, summary: summary(cost: 0.0625, tokensIn: 12_480, tokensOut: 610)
        )

        let seed = try seed(meetings: [kept])

        #expect(seed.days == [DayRow(day: "2026-10-13", spend: [
            "meeting": Spend(usd: 0.375, seconds: ["speechmatics_enhanced": 3_600]),
            "summary": Spend(usd: 0.09375, tokensIn: 12_480, tokensOut: 610),
            "naming": Spend(usd: 0.015625),
        ])])
        #expect(seed.meetingsWithCost == 1)
    }

    @Test func currentMonthUnfinishedTestAndCostlessMeetingsAddNothingBesideAKeptEarlierOne() throws {
        let billing = Billing(engineSeconds: 600, costUSD: 0.25)
        let meetings = [
            try meeting(started: "2026-10-31T22:30:00+00:00", ended: "2026-10-31T23:00:00+00:00", billing: billing),
            try meeting(started: "2026-11-02T10:00:00+01:00", ended: "2026-11-02T11:00:00+01:00", billing: billing),
            try meeting(started: "2026-10-31T23:30:00+00:00", ended: "2026-11-01T00:30:00+00:00", billing: billing),
            try meeting(started: "2026-10-05T10:00:00+02:00", ended: nil, billing: billing),
            try meeting(
                started: "2026-10-06T10:00:00+02:00", ended: "2026-10-06T10:20:00+02:00", billing: billing,
                summary: summary(cost: 0.125), test: Self.testCall
            ),
            try meeting(started: "2026-10-07T10:00:00+02:00", ended: "2026-10-07T11:00:00+02:00"),
        ]

        let seed = try seed(meetings: meetings)

        #expect(seed.days == [DayRow(day: "2026-10-31", spend: [
            "meeting": Spend(usd: 0.25, seconds: ["speechmatics": 600]),
        ])])
        #expect(seed.meetingsWithCost == 1)
    }

    // MARK: - All three

    @Test func seededSpendIsEachCostOnceWithNoOverlap() throws {
        let history = [
            try entry("old", at: "2026-10-10T09:00:00+02:00", cost: 0.125),
            try entry("new", at: "2026-11-05T09:00:00+01:00", cost: 0.0625),
        ]
        let usage = ["2026-11-05": DayUsage(inputTokens: 900, streamedSeconds: ["speechmatics": 1_800], costUSD: 0.5)]
        let earlier = try meeting(
            started: "2026-10-14T10:00:00+02:00", ended: "2026-10-14T11:00:00+02:00",
            billing: Billing(
                engineSeconds: 3_600, costUSD: 0.375, replacedSummaryCostUSD: 0.03125, namingCostUSD: 0.015625
            ),
            summary: summary(cost: 0.0625)
        )
        let thisMonth = try meeting(
            started: "2026-11-05T10:00:00+01:00", ended: "2026-11-05T10:30:00+01:00",
            billing: Billing(engineSeconds: 1_800, costUSD: 0.25), summary: summary(cost: 0.0625)
        )

        let seed = try seed(history: history, usage: usage, meetings: [thisMonth, earlier])

        let expected = 0.125 + 0.5 + earlier.totalCostUSD
        #expect(abs(totalUSD(seed) - expected) < 1e-9)
        #expect(seed.days.map(\.day) == ["2026-10-10", "2026-10-14", "2026-11-05"])
        #expect(seed.days.map { $0.spend.keys.sorted() } == [
            ["dictation"], ["meeting", "naming", "summary"], ["unsplit"],
        ])
    }

    // MARK: - Security

    @Test func theSeedHoldsNoTextTitleOrName() throws {
        let northwind = MeetingFixtures.northwind().meeting
        var test = MeetingFixtures.make(
            title: "Standup rehearsal with Priya",
            test: TestCallTag(scenarioID: "standup", revision: 1, scenarioTitle: "Morning standup")
        ).meeting
        test.startedAt = try date("2026-12-01T09:00:00+01:00")
        test.endedAt = try date("2026-12-01T09:10:00+01:00")
        test.billing = Billing(engineSeconds: 600, costUSD: 0.0625)
        let history = [
            try entry("h", at: "2026-11-20T09:00:00+01:00", text: "Tell Marta the demo moved", cost: 0.125),
        ]

        let seed = try seed(
            history: history, usage: ["2026-12-01": DayUsage(costUSD: 0.5)], meetings: [northwind, test],
            now: "2026-12-02T10:00:00+01:00"
        )

        #expect(seed.dictations.count == 1)
        #expect(seed.meetingsWithCost == 1)
        let encoder = JSONEncoder()
        let bytes = try encoder.encode(seed.dictations) + encoder.encode(seed.days)
        let written = String(decoding: bytes, as: UTF8.self)
        let names = northwind.speakers.map(\.name) + [northwind.userName]
        let text = [
            northwind.title, test.title, "Morning standup", "Tell Marta the demo moved", "Mail",
            String(try #require(northwind.summary?.text.split(separator: "\n").last)),
        ]
        for forbidden in names + text {
            #expect(!written.contains(forbidden), "\(forbidden)")
        }
    }
}
