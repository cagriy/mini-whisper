import Foundation
import Testing

import MWStats

@Suite struct SidebarStatsTests {
    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    private func instant(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    /// At 2026-11-25 12:00 UTC, so the window runs from 2026-10-27 to 2026-11-25.
    private func sidebar(_ snapshot: StatsSnapshot, typingWPM: Int = 40) throws -> SidebarStats? {
        SidebarStats(
            snapshot: snapshot, typingWPM: typingWPM, now: try instant("2026-11-25T12:00:00Z"),
            calendar: try calendar("UTC")
        )
    }

    private func meeting(_ at: String, seconds: TimeInterval, words: Int = 0) -> MeetingRow {
        MeetingRow(id: UUID(), at: at, duration: seconds, words: words)
    }

    @Test func nothingUntilACountedMeetingOrADeliveredDictation() throws {
        let short = meeting("2026-11-25T09:00:00+00:00", seconds: 59)
        let undelivered = DayRow(day: "2026-11-25", undelivered: ["too_short": 2], spend: ["unsplit": Spend(usd: 1)])

        #expect(try sidebar(StatsSnapshot()) == nil)
        #expect(try sidebar(StatsSnapshot(days: [undelivered], meetings: [short])) == nil)
        #expect(try sidebar(StatsSnapshot(meetings: [meeting("2026-11-25T09:00:00+00:00", seconds: 60)])) != nil)
        #expect(try sidebar(StatsSnapshot(days: [DayRow(day: "2026-11-25", delivered: 1)])) != nil)
    }

    @Test func aFigureWithNothingInTheWindowIsZero() throws {
        let stats = try #require(try sidebar(StatsSnapshot(
            days: [DayRow(day: "2024-03-01", delivered: 4, words: 90, seconds: 20, timedWords: 90)],
            meetings: [meeting("2024-03-01T09:00:00+00:00", seconds: 3_600, words: 500)]
        )))

        #expect(stats.meetings == 0)
        #expect(stats.recorded == 0)
        #expect(stats.dictations == 0)
        #expect(stats.savedTyping == 0)
        #expect(stats.wordsTranscribed == 0)
        #expect(stats.wordsDictated == 0)
        #expect(stats.trend == Array(repeating: 0, count: 30))
    }

    // London leaves summer time on 2026-10-25, inside the last window: counting back 29 × 24 h
    // from 23:30 would start it a day late.
    @Test(arguments: [
        ("UTC", "2026-11-25T12:00:00Z", "2026-10-26", "2026-10-27", "2026-11-25", "2026-11-26"),
        ("Asia/Tokyo", "2026-11-24T20:00:00Z", "2026-10-26", "2026-10-27", "2026-11-25", "2026-11-26"),
        ("Europe/London", "2026-11-22T23:30:00Z", "2026-10-23", "2026-10-24", "2026-11-22", "2026-11-23"),
    ])
    func theWindowIsTodayAndThe29LocalDaysBefore(
        _ zone: String, _ now: String, _ before: String, _ first: String, _ today: String, _ after: String
    ) throws {
        let snapshot = StatsSnapshot(days: [
            DayRow(day: before, delivered: 1), DayRow(day: first, delivered: 10),
            DayRow(day: today, delivered: 100), DayRow(day: after, delivered: 1_000),
        ])

        let stats = try #require(SidebarStats(
            snapshot: snapshot, typingWPM: 40, now: try instant(now), calendar: try calendar(zone)
        ))

        #expect(stats.dictations == 110)
    }

    @Test func aMeetingCountsOnTheLocalDayItStarted() throws {
        let stats = try #require(try sidebar(StatsSnapshot(meetings: [
            // 26 October in UTC, 27 October where it took place: inside.
            meeting("2026-10-27T00:30:00+09:00", seconds: 600, words: 10),
            // 27 October in UTC, 26 October where it took place: outside.
            meeting("2026-10-26T23:30:00-05:00", seconds: 1_200, words: 20),
        ])))

        #expect(stats.meetings == 1)
        #expect(stats.recorded == 600)
        #expect(stats.wordsTranscribed == 10)
        #expect(stats.trend.first == 600)
    }

    @Test func meetingsUnderAMinuteAreLeftOut() throws {
        let stats = try #require(try sidebar(StatsSnapshot(meetings: [
            meeting("2026-11-25T09:00:00+00:00", seconds: 59.9, words: 300),
            meeting("2026-11-25T10:00:00+00:00", seconds: 60, words: 7),
        ])))

        #expect(stats.meetings == 1)
        #expect(stats.recorded == 60)
        #expect(stats.wordsTranscribed == 7)
        #expect(stats.trend.last == 60)
        #expect(stats.lifetimeMeetings == 1)
        #expect(stats.lifetimeRecorded == 60)
    }

    @Test func theSixFiguresSumTheWindow() throws {
        let stats = try #require(try sidebar(StatsSnapshot(
            days: [
                DayRow(day: "2026-10-20", delivered: 50, words: 5_000, seconds: 900, timedWords: 5_000),
                DayRow(day: "2026-11-01", delivered: 3, words: 120, seconds: 30, timedWords: 100),
                DayRow(day: "2026-11-25", delivered: 2, words: 80, seconds: 30, timedWords: 60),
            ],
            meetings: [
                meeting("2026-10-20T10:00:00+00:00", seconds: 7_200, words: 20_000),
                meeting("2026-11-02T10:00:00+00:00", seconds: 3_600, words: 9_000),
                meeting("2026-11-25T08:00:00+00:00", seconds: 1_800, words: 4_000),
            ]
        )))

        #expect(stats.meetings == 2)
        #expect(stats.recorded == 5_400)
        #expect(stats.dictations == 5)
        // 160 timed words take 4 minutes to type and took 1 to say.
        #expect(stats.savedTyping == 180)
        #expect(stats.wordsTranscribed == 13_000)
        #expect(stats.wordsDictated == 200)
    }

    // 1,200 timed words said in 11 minutes take 30, 15 and 10 minutes to type. A speed of zero
    // saves nothing rather than dividing by it.
    @Test(arguments: [(40, 1_140), (80, 240), (120, 0), (0, 0)] as [(Int, TimeInterval)])
    func savedTypingFollowsTheTypingSpeed(_ typingWPM: Int, _ saved: TimeInterval) throws {
        let snapshot = StatsSnapshot(days: [
            DayRow(day: "2026-11-03", delivered: 4, words: 900, seconds: 300, timedWords: 700),
            DayRow(day: "2026-11-20", delivered: 4, words: 500, seconds: 360, timedWords: 500),
        ])

        #expect(try #require(try sidebar(snapshot, typingWPM: typingWPM)).savedTyping == saved)
    }

    @Test func theTrendIsThirtyDaysOfTimeRecordedOldestFirst() throws {
        let stats = try #require(try sidebar(StatsSnapshot(meetings: [
            meeting("2026-10-27T09:00:00+00:00", seconds: 1_800),
            meeting("2026-11-15T09:00:00+00:00", seconds: 3_600),
            meeting("2026-11-20T09:00:00+00:00", seconds: 30),
            meeting("2026-11-25T09:00:00+00:00", seconds: 600),
            meeting("2026-11-25T14:00:00+00:00", seconds: 1_200),
        ])))
        var expected = [TimeInterval](repeating: 0, count: 30)
        expected[0] = 1_800
        expected[19] = 3_600
        expected[29] = 1_800

        #expect(stats.trend == expected)
    }

    @Test func theLifetimeLineCountsEveryCountedMeeting() throws {
        let stats = try #require(try sidebar(StatsSnapshot(meetings: [
            meeting("2026-11-25T09:00:00+00:00", seconds: 3_600),
            meeting("2023-02-01T09:00:00+00:00", seconds: 7_200),
            // No readable start: on no day, but still a counted meeting.
            meeting("", seconds: 1_800),
            meeting("2026-11-25T10:00:00+00:00", seconds: 59),
        ])))

        #expect(stats.lifetimeMeetings == 3)
        #expect(stats.lifetimeRecorded == 12_600)
        #expect(stats.meetings == 1)
    }
}
