import Foundation
import Testing

import MWStats

@Suite struct TimelineStatsTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func report(
        meetings: [MeetingRow] = [], days: [DayRow] = [], dictations: [DictationRow] = [],
        kept: [UUID: TimelineInputs.KeptMeeting] = [:], typingWPM: Int = 40,
        now: String = "2026-11-25T12:00:00Z", zone: String = "UTC", firstWeekday: Int = 2
    ) throws -> TimelineReport {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        calendar.firstWeekday = firstWeekday
        return TimelineStats.compute(TimelineInputs(
            snapshot: StatsSnapshot(dictations: dictations, days: days, meetings: meetings), kept: kept,
            typingWPM: typingWPM, now: try #require(ISO8601DateFormatter().date(from: now)), calendar: calendar
        ))
    }

    private func meeting(_ at: String, end: String = "", seconds: Double = 1_800, words: Int = 0) -> MeetingRow {
        MeetingRow(id: UUID(), at: at, end: end, duration: seconds, words: words)
    }

    /// Counted meetings of half an hour at 09:00 UTC on 1 January 2026 and the days after.
    private func filler(_ count: Int) -> [MeetingRow] {
        (1...count).map { day in
            let date = String(format: "2026-01-%02d", day)
            return meeting("\(date)T09:00:00+00:00", end: "\(date)T09:30:00+00:00")
        }
    }

    private func speaking(
        _ at: String, seconds: Double = 1_800, speech: Double, user: Int?, userKnown: Bool = true,
        speakers: [MeetingRow.Speaker]
    ) -> MeetingRow {
        MeetingRow(
            id: UUID(), at: at, duration: seconds, speech: speech, user: user, userKnown: userKnown,
            speakers: speakers, questions: 99
        )
    }

    private func calendarYear(_ year: Int, of report: TimelineReport) throws -> TimelineReport.CalendarYear {
        try #require(report.year?.years.first { $0.year == year })
    }

    private func day(_ key: String, in grid: TimelineReport.YearGrid) -> TimelineReport.Day? {
        grid.weeks.joined().compactMap { $0 }.first { $0.key == key }
    }

    /// Seven rows of 24 hours, so indexing cannot trap.
    private func shaped(_ grid: TimelineReport.RhythmGrid?) throws -> TimelineReport.RhythmGrid {
        let grid = try #require(grid)
        try #require(grid.counts.count == 7 && grid.counts.allSatisfy { $0.count == 24 })
        try #require(grid.levels.count == 7 && grid.levels.allSatisfy { $0.count == 24 })
        return grid
    }

    private func weekday(_ key: String) -> Int? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Self.utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        return Self.utc.component(.weekday, from: date)
    }

    @Test func anEmptyRecordShowsNoPanelButKeepsTheWeekOrder() throws {
        let result = try report()

        #expect(result.weekdays == [2, 3, 4, 5, 6, 7, 1])
        #expect(result.totals == nil)
        #expect(result.year == nil)
        #expect(result.rhythm == nil)
        #expect(result.talkShare == nil)
        #expect(result.spend == nil)
        #expect(result.dictation == nil)
        #expect(result.records == nil)
        #expect(result.milestones == nil)
    }

    // MARK: - Lifetime totals

    @Test func totalsAppearAtOneCountedMeeting() throws {
        let short = meeting("2026-03-02T09:00:00+00:00", seconds: 59, words: 40)
        let undelivered = DayRow(day: "2026-03-02", undelivered: ["too_short": 3], spend: ["meeting": Spend(usd: 0.5)])

        #expect(try report(meetings: [short], days: [undelivered]).totals == nil)
        #expect(try report(meetings: [short, meeting("2026-03-03T09:00:00+00:00", seconds: 60)], days: [undelivered]).totals?.meetings == 1)
    }

    @Test func totalsAppearAtOneDeliveredDictation() throws {
        let totals = try #require(try report(days: [DayRow(day: "2026-03-02", delivered: 1, words: 9)]).totals)

        #expect(totals.dictations == 1)
        #expect(totals.meetings == nil)
        #expect(totals.recorded == nil)
        #expect(totals.wordsTranscribed == nil)
        #expect(totals.spend == nil)
    }

    @Test func totalsSumTheWholeRecord() throws {
        let totals = try #require(try report(
            meetings: [
                meeting("2026-03-02T09:00:00+00:00", seconds: 3_600, words: 1_000),
                meeting("2024-07-01T09:00:00+00:00", seconds: 1_800, words: 500),
                meeting("2026-03-02T11:00:00+00:00", seconds: 30, words: 50),
            ],
            days: [
                DayRow(day: "2024-07-01", delivered: 3, spend: ["dictation": Spend(usd: 0.25), "meeting": Spend(usd: 0.5)]),
                DayRow(day: "2026-03-02", delivered: 4, undelivered: ["silent": 2], spend: [
                    "unsplit": Spend(usd: 1.25), "summary": Spend(usd: 0.125), "naming": Spend(usd: 0.0625),
                ]),
            ]
        ).totals)

        #expect(totals.meetings == 2)
        #expect(totals.recorded == 5_400)
        #expect(totals.wordsTranscribed == 1_500)
        #expect(totals.dictations == 7)
        // Every purpose of every day, a short meeting's cost included.
        #expect(totals.spend == 2.1875)
    }

    @Test func aZeroTotalIsLeftOut() throws {
        let totals = try #require(try report(meetings: [meeting("2026-03-02T09:00:00+00:00", seconds: 60)]).totals)

        #expect(totals.meetings == 1)
        #expect(totals.recorded == 60)
        #expect(totals.wordsTranscribed == nil)
        #expect(totals.dictations == nil)
        #expect(totals.spend == nil)
    }

    // MARK: - The year

    @Test func theYearAppearsAtOneActiveDay() throws {
        let short = meeting("2026-03-02T09:00:00+00:00", seconds: 59)
        let undelivered = DayRow(day: "2026-03-02", undelivered: ["too_short": 1])

        #expect(try report(meetings: [short], days: [undelivered]).year == nil)
        let year = try #require(try report(meetings: [short], days: [undelivered, DayRow(day: "2026-03-04", delivered: 1)]).year)
        #expect(year.years.map(\.year) == [2026])
    }

    // 1 January 2026 is a Thursday, 2028 a Saturday and 2040 a Sunday; 2028 and 2040 are leap years.
    @Test(arguments: [
        (2026, 2, 3, 53), (2026, 1, 4, 53),
        (2028, 2, 5, 53), (2028, 1, 6, 54),
        (2040, 2, 6, 54), (2040, 1, 0, 53),
    ])
    func weekColumnsRunFromTheCalendarsFirstWeekday(_ year: Int, _ firstWeekday: Int, _ lead: Int, _ columns: Int) throws {
        let result = try report(
            days: [DayRow(day: "\(year)-03-01", delivered: 1)], now: "\(year)-06-01T12:00:00Z", firstWeekday: firstWeekday
        )
        let entry = try calendarYear(year, of: result)

        try #require(result.weekdays == (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 })
        for grid in [entry.meetings, entry.dictation] {
            #expect(grid.weeks.count == columns)
            try #require(!grid.weeks.isEmpty && grid.weeks.allSatisfy { $0.count == 7 })
            #expect(grid.weeks[0].prefix(lead).allSatisfy { $0 == nil })
            #expect(grid.weeks[0][lead]?.key == "\(year)-01-01")
            let days = grid.weeks.joined().compactMap { $0 }
            #expect(days.count == (year % 4 == 0 ? 366 : 365))
            #expect(days.last?.key == "\(year)-12-31")
            #expect(zip(days, days.dropFirst()).allSatisfy { $0.key < $1.key })
            let misplaced = grid.weeks.flatMap { week in
                week.enumerated().compactMap { row, day in
                    day.flatMap { weekday($0.key) == result.weekdays[row] ? nil : $0.key }
                }
            }
            #expect(misplaced.isEmpty)
        }
    }

    @Test func meetingHeatIsTimeRecordedADay() throws {
        let entry = try calendarYear(2026, of: try report(meetings: [
            meeting("2026-03-02T09:00:00+00:00", seconds: 59),
            meeting("2026-03-03T09:00:00+00:00", seconds: 60),
            meeting("2026-03-04T09:00:00+00:00", seconds: 3_599),
            meeting("2026-03-05T09:00:00+00:00", seconds: 3_600),
            meeting("2026-03-06T09:00:00+00:00", seconds: 7_199),
            meeting("2026-03-07T09:00:00+00:00", seconds: 7_200),
            meeting("2026-03-08T09:00:00+00:00", seconds: 14_399),
            meeting("2026-03-09T09:00:00+00:00", seconds: 14_400),
            meeting("2026-03-10T09:00:00+00:00", seconds: 1_800),
            meeting("2026-03-10T15:00:00+00:00", seconds: 1_800),
        ]))
        let keys = (2...11).map { String(format: "2026-03-%02d", $0) }

        #expect(keys.map { day($0, in: entry.meetings)?.level } == [0, 1, 1, 2, 2, 3, 3, 4, 2, 0])
        #expect(day("2026-03-10", in: entry.meetings)?.amount == 3_600)
        #expect(day("2026-03-02", in: entry.meetings)?.amount == 0)
    }

    @Test func dictationHeatIsDictationsDeliveredADay() throws {
        let counts = [1, 5, 6, 15, 16, 40, 41]
        var days = counts.enumerated().map { index, count in
            DayRow(day: String(format: "2026-04-%02d", index + 1), delivered: count)
        }
        days.append(DayRow(day: "2026-04-08", undelivered: ["empty": 4]))

        let entry = try calendarYear(2026, of: try report(days: days))

        #expect((1...8).map { day(String(format: "2026-04-%02d", $0), in: entry.dictation)?.level } == [1, 1, 2, 2, 3, 3, 4, 0])
        #expect(day("2026-04-07", in: entry.dictation)?.amount == 41)
        #expect(day("2026-04-07", in: entry.meetings)?.level == 0)
    }

    @Test func aMeetingCountsOnTheLocalDayItStartedAtItsOwnOffset() throws {
        let result = try report(
            meetings: [
                meeting("2026-03-02T23:30:00-05:00", seconds: 600),
                meeting("2026-12-31T23:30:00-05:00", seconds: 900),
            ],
            now: "2027-01-15T12:00:00Z"
        )
        let year2026 = try calendarYear(2026, of: result)
        let year2027 = try calendarYear(2027, of: result)

        #expect(day("2026-03-02", in: year2026.meetings)?.amount == 600)
        #expect(day("2026-03-03", in: year2026.meetings)?.amount == 0)
        #expect(day("2026-12-31", in: year2026.meetings)?.amount == 900)
        #expect(day("2027-01-01", in: year2027.meetings)?.amount == 0)
        #expect(year2027.activeDays == 0)
    }

    @Test func theCaptionCountsActiveDaysAndTheLongestStreakWithinTheYear() throws {
        let result = try report(
            meetings: [
                meeting("2026-12-30T10:00:00+00:00"),
                meeting("2027-01-02T10:00:00+00:00"),
                meeting("2026-12-29T10:00:00+00:00", seconds: 30),
            ],
            days: [
                DayRow(day: "2026-06-01", delivered: 2),
                DayRow(day: "2026-12-29", undelivered: ["silent": 1]),
                DayRow(day: "2026-12-31", delivered: 1),
                DayRow(day: "2027-01-01", delivered: 1),
            ],
            now: "2027-03-01T12:00:00Z"
        )
        let year2026 = try calendarYear(2026, of: result)
        let year2027 = try calendarYear(2027, of: result)

        #expect(year2026.activeDays == 3)
        #expect(year2026.longestStreak == Streak(days: 2, first: "2026-12-30", last: "2026-12-31"))
        #expect(year2026.dictationDays == 2)
        #expect(year2027.activeDays == 2)
        #expect(year2027.longestStreak == Streak(days: 2, first: "2027-01-01", last: "2027-01-02"))
        #expect(year2027.dictationDays == 1)
    }

    // Tokyo is already in 2027 at 20:00 UTC on 31 December 2026. A day past this year, from a
    // wrong clock, extends nothing.
    @Test func theYearsRunFromTheEarliestYearWithDataToThisYear() throws {
        let result = try report(
            meetings: [meeting("2026-05-05T09:00:00+00:00")],
            days: [DayRow(day: "2024-05-05", delivered: 1), DayRow(day: "2028-01-05", delivered: 1)],
            now: "2026-12-31T20:00:00Z", zone: "Asia/Tokyo"
        )
        let years = try #require(result.year).years
        let empty = try calendarYear(2025, of: result)

        #expect(years.map(\.year) == [2024, 2025, 2026, 2027])
        #expect(empty.activeDays == 0)
        #expect(empty.longestStreak == nil)
        #expect(empty.dictationDays == 0)
        #expect(empty.meetings.weeks.joined().allSatisfy { ($0?.level ?? 0) == 0 })
        #expect(empty.dictation.weeks.joined().allSatisfy { ($0?.level ?? 0) == 0 })
    }

    // MARK: - Weekly rhythm

    @Test func theRhythmAppearsAtTenCountedMeetings() throws {
        let short = (1...3).map { meeting(String(format: "2026-02-%02dT09:00:00+00:00", $0), seconds: 59) }

        #expect(try report(meetings: filler(9) + short).rhythm == nil)
        #expect(try report(meetings: filler(10) + short).rhythm != nil)
    }

    @Test func theDictationSwitchAppearsAtFiftyDelivered() throws {
        let below = try report(meetings: filler(10), days: [DayRow(day: "2026-03-03", delivered: 49, hours: ["9": 49])])
        let at = try report(meetings: filler(10), days: [DayRow(day: "2026-03-03", delivered: 50, hours: ["9": 50])])

        #expect(try #require(below.rhythm).dictation == nil)
        #expect(try #require(at.rhythm).dictation != nil)
    }

    // The meetings start on Mondays at 07:00 where they took place, which is Sunday in UTC; the
    // dictations fall on a Tuesday.
    @Test(arguments: [(2, 0, 1), (1, 1, 2)])
    func rhythmRowsRunFromTheCalendarsFirstWeekday(_ firstWeekday: Int, _ mondayRow: Int, _ tuesdayRow: Int) throws {
        let mondays = ["03-02", "03-09", "03-16", "03-23", "03-30", "04-06", "04-13", "04-20", "04-27", "05-04"]
        let result = try report(
            meetings: mondays.map { meeting("2026-\($0)T07:10:00+09:00") },
            days: [DayRow(day: "2026-03-03", delivered: 50, hours: ["21": 50])],
            firstWeekday: firstWeekday
        )
        let meetings = try shaped(result.rhythm?.meetings)
        let dictation = try shaped(result.rhythm?.dictation)

        #expect(meetings.counts[mondayRow][7] == 10)
        #expect(meetings.counts.joined().reduce(0, +) == 10)
        #expect(meetings.busiest == TimelineReport.Slot(weekday: 2, hour: 7))
        #expect(dictation.counts[tuesdayRow][21] == 50)
        #expect(dictation.busiest == TimelineReport.Slot(weekday: 3, hour: 21))
    }

    // Quarters of 12 are 3, 6 and 9: a cell at a quarter stays in the level below it.
    @Test func rhythmLevelsAreQuartersOfTheLargestCell() throws {
        let hours = [12, 10, 9, 7, 6, 4, 3, 1]
        let result = try report(
            meetings: filler(10),
            days: [DayRow(
                day: "2026-03-03", delivered: 52,
                hours: Dictionary(uniqueKeysWithValues: hours.enumerated().map { ("\($0.offset)", $0.element) })
            )]
        )
        let meetings = try shaped(result.rhythm?.meetings)
        let dictation = try shaped(result.rhythm?.dictation)

        #expect(Array(dictation.levels[1].prefix(9)) == [4, 4, 3, 3, 2, 2, 1, 1, 0])
        #expect(dictation.levels.joined().reduce(0, +) == 20)
        // 1 to 10 January at 09:00: two on Thursday, Friday and Saturday, one on the other days.
        #expect(meetings.levels.map { $0[9] } == [2, 2, 2, 4, 4, 4, 2])
        #expect(meetings.levels.joined().reduce(0, +) == 20)
    }

    // Four meetings at 09:00 on Sundays and four on Mondays: the later row wins, which is Sunday
    // in a week starting Monday and Monday in one starting Sunday. Of two equal hours, the later.
    @Test(arguments: [(2, 1), (1, 2)])
    func ofEqualCellsTheLaterInTheGridIsTheBusiest(_ firstWeekday: Int, _ busiestWeekday: Int) throws {
        let meetings = ["03-01", "03-08", "03-15", "03-22", "03-02", "03-09", "03-16", "03-23"]
            .map { meeting("2026-\($0)T09:00:00+00:00") }
            + [meeting("2026-03-30T08:00:00+00:00"), meeting("2026-04-06T10:00:00+00:00")]
        let result = try report(
            meetings: meetings, days: [DayRow(day: "2026-03-03", delivered: 50, hours: ["9": 25, "14": 25])],
            firstWeekday: firstWeekday
        )
        let rhythm = try #require(result.rhythm)

        #expect(rhythm.meetings.busiest == TimelineReport.Slot(weekday: busiestWeekday, hour: 9))
        #expect(rhythm.dictation?.busiest == TimelineReport.Slot(weekday: 3, hour: 14))
    }

    @Test func backToBackMeansStartingWithin300SecondsOfThePreviousCountedEnd() throws {
        let meetings = [
            meeting("2026-03-02T09:00:00+00:00", end: "2026-03-02T10:00:00+00:00"),
            // 0 s after.
            meeting("2026-03-02T10:00:00+00:00", end: "2026-03-02T10:30:00+00:00"),
            // 300 s after.
            meeting("2026-03-02T10:35:00+00:00", end: "2026-03-02T11:00:00+00:00"),
            // 301 s after.
            meeting("2026-03-02T11:05:01+00:00", end: "2026-03-02T11:30:00+00:00"),
            // Before the previous one ended.
            meeting("2026-03-02T11:29:59+00:00", end: "2026-03-02T12:00:00+00:00"),
            // Under a minute: not a previous meeting.
            meeting("2026-03-02T12:20:00+00:00", end: "2026-03-02T12:20:30+00:00", seconds: 30),
            // 90 s after the short one, 22 minutes after the last counted one.
            meeting("2026-03-02T13:22:00+01:00", end: "2026-03-02T13:52:00+01:00"),
            // 180 s after, at another offset.
            meeting("2026-03-02T21:55:00+09:00", end: "2026-03-02T22:20:00+09:00"),
        ] + filler(3)

        let rhythm = try #require(try report(meetings: meetings.reversed()).rhythm)

        #expect(rhythm.backToBack == 3)
    }

    @Test func theEarliestStartAndTheLatestFinishAreLocalTimesOfDay() throws {
        let meetings = [
            // 21:45 the day before in UTC.
            meeting("2026-03-02T06:45:00+09:00", end: "2026-03-02T07:30:00+09:00"),
            // Ends on the next day, so at 24:30.
            meeting("2026-03-03T23:00:00+00:00", end: "2026-03-04T00:30:00+00:00"),
            // 04:59 the next day in UTC.
            meeting("2026-03-05T20:00:00-05:00", end: "2026-03-05T23:59:00-05:00"),
            // Under a minute.
            meeting("2026-03-06T05:00:00+00:00", end: "2026-03-07T02:00:30+00:00", seconds: 30),
        ] + filler(7)

        let rhythm = try #require(try report(meetings: meetings).rhythm)

        #expect(rhythm.earliestStart == TimeInterval(6 * 3_600 + 45 * 60))
        #expect(rhythm.latestFinish == TimeInterval(24 * 3_600 + 30 * 60))
    }

    // MARK: - Talk share

    @Test func talkShareAppearsAtThreeCountedMeetingsWithTheUserKnown() throws {
        let speakers = [MeetingRow.Speaker(id: 0, seconds: 60)]
        let known = [
            speaking("2026-03-02T09:00:00+00:00", speech: 100, user: 0, speakers: speakers),
            speaking("2026-03-03T09:00:00+00:00", speech: 100, user: 0, speakers: speakers),
        ]
        let others = [
            speaking("2026-03-04T09:00:00+00:00", seconds: 59, speech: 100, user: 0, speakers: speakers),
            speaking("2026-03-05T09:00:00+00:00", speech: 100, user: nil, userKnown: false, speakers: speakers),
        ]
        let third = speaking("2026-03-06T09:00:00+00:00", speech: 100, user: 0, speakers: speakers)

        #expect(try report(meetings: known + others).talkShare == nil)
        #expect(try report(meetings: known + others + [third]).talkShare?.meetings == 3)
    }

    @Test func talkShareIsTheUsersSecondsOverSpeech() throws {
        let meetings = [
            speaking("2026-03-04T09:00:00+00:00", speech: 200, user: nil, speakers: [MeetingRow.Speaker(id: 1, seconds: 200)]),
            speaking("2026-03-02T09:00:00+00:00", speech: 600, user: 0, speakers: [
                MeetingRow.Speaker(id: 0, seconds: 120, words: 300, questions: 2),
                MeetingRow.Speaker(id: 1, seconds: 480, words: 900, questions: 5),
            ]),
            speaking("2026-03-05T09:00:00+00:00", speech: 1_000, user: 0, userKnown: false, speakers: [
                MeetingRow.Speaker(id: 0, seconds: 1_000, words: 2_000, questions: 9),
            ]),
            speaking("2026-03-03T09:00:00+00:00", speech: 1_200, user: 3, speakers: [
                MeetingRow.Speaker(id: 1, seconds: 600, words: 1_000, questions: 1),
                MeetingRow.Speaker(id: 3, seconds: 600, words: 1_500, questions: 4),
            ]),
            speaking("2026-03-06T09:00:00+00:00", seconds: 59, speech: 50, user: 0, speakers: [
                MeetingRow.Speaker(id: 0, seconds: 50, words: 100, questions: 3),
            ]),
        ]

        let share = try #require(try report(meetings: meetings).talkShare)

        #expect(share.meetings == 3)
        // 720 of 2,000 s.
        #expect(share.share == 0.36)
        // 1,800 words in 12 minutes.
        #expect(share.wordsPerMinute == 150)
        #expect(share.questions == 6)
        #expect(share.recent == [0.2, 0.5, 0])
    }

    @Test func theLastTwentySharesRunOldestFirst() throws {
        let meetings = (0..<22).map { index in
            speaking(
                String(format: "2026-03-%02dT09:00:00+00:00", index + 1), speech: 100, user: 0,
                speakers: [MeetingRow.Speaker(id: 0, seconds: Double(index))]
            )
        }

        let share = try #require(try report(meetings: Array(meetings.suffix(11) + meetings.prefix(11))).talkShare)

        #expect(share.meetings == 22)
        #expect(share.recent == (2..<22).map { Double($0) / 100 })
    }

    // MARK: - Spend

    @Test func spendAppearsAtOneDayWithACost() throws {
        var costly = meeting("2026-03-02T09:00:00+00:00", seconds: 600)
        costly.usd = MeetingRow.Costs(meeting: 0.5)
        let free = DayRow(day: "2026-03-02", delivered: 3, spend: ["dictation": Spend(usd: 0, tokensIn: 40)])

        #expect(try report(meetings: [costly], days: [free]).spend == nil)
        // Long before the months shown.
        let old = DayRow(day: "2024-01-05", spend: ["naming": Spend(usd: 0.01)])
        #expect(try report(meetings: [costly], days: [free, old]).spend != nil)
    }

    // 23:30 UTC on 30 November is already 1 December in Tokyo.
    @Test(arguments: [("UTC", 2025, 12), ("Asia/Tokyo", 2026, 1)])
    func spendRunsTwelveMonthsEndingThisMonth(_ zone: String, _ firstYear: Int, _ firstMonth: Int) throws {
        let spend = try #require(try report(
            days: [DayRow(day: "2026-06-10", spend: ["meeting": Spend(usd: 1)])], now: "2026-11-30T23:30:00Z", zone: zone
        ).spend)
        let expected = (0..<12).map { offset in
            let index = firstYear * 12 + firstMonth - 1 + offset
            return [index / 12, index % 12 + 1]
        }

        #expect(spend.months.map { [$0.year, $0.month] } == expected)
    }

    @Test func aMonthStacksItsDaysByPurpose() throws {
        let spend = try #require(try report(days: [
            // The month before the first shown.
            DayRow(day: "2025-11-30", spend: ["meeting": Spend(usd: 8)]),
            DayRow(day: "2025-12-01", spend: ["dictation": Spend(usd: 0.25), "naming": Spend(usd: 0, tokensIn: 5)]),
            DayRow(day: "2026-03-02", spend: ["meeting": Spend(usd: 1), "summary": Spend(usd: 0.5)]),
            DayRow(day: "2026-03-31", spend: ["meeting": Spend(usd: 0.25), "naming": Spend(usd: 0.125)]),
            DayRow(day: "2026-11-25", spend: ["unsplit": Spend(usd: 2), "dictation": Spend(usd: 0.5)]),
        ]).spend)

        try #require(spend.months.count == 12)
        #expect(spend.months[0].amounts == [.dictation: 0.25])
        #expect(spend.months[3].amounts == [.meeting: 1.25, .summary: 0.5, .naming: 0.125])
        #expect(spend.months[11].amounts == [.unsplit: 2, .dictation: 0.5])
        #expect(spend.months.count { $0.amounts.isEmpty } == 9)
    }

    @Test func theSeriesAreThosePresentInTheShownMonthsInStackingOrder() throws {
        let spend = try #require(try report(days: [
            DayRow(day: "2025-11-30", spend: ["summary": Spend(usd: 1), "unsplit": Spend(usd: 1)]),
            DayRow(day: "2026-02-02", spend: ["naming": Spend(usd: 0.25)]),
            DayRow(day: "2026-11-02", spend: ["meeting": Spend(usd: 0), "dictation": Spend(usd: 0.25)]),
        ]).spend)

        #expect(spend.series == [.dictation, .naming])
        #expect(!spend.showsUnsplitCaption)
    }

    @Test func theUnsplitCaptionShowsWhileAShownMonthHasAnUnsplitPart() throws {
        let shown = try #require(try report(days: [DayRow(day: "2026-11-01", spend: ["unsplit": Spend(usd: 3.1)])]).spend)
        let earlier = try #require(try report(days: [DayRow(day: "2025-11-30", spend: ["unsplit": Spend(usd: 3.1)])]).spend)

        #expect(shown.series == [.unsplit])
        #expect(shown.showsUnsplitCaption)
        #expect(earlier.series.isEmpty)
        #expect(!earlier.showsUnsplitCaption)
    }

    // Tokyo is already in 2027 at 20:00 UTC on 31 December 2026.
    @Test func spendThisYearAndAllTime() throws {
        let days = [
            DayRow(day: "2024-06-01", spend: ["meeting": Spend(usd: 4)]),
            DayRow(day: "2025-12-31", spend: ["dictation": Spend(usd: 0.5)]),
            DayRow(day: "2026-01-01", spend: ["unsplit": Spend(usd: 1), "summary": Spend(usd: 0.25)]),
            DayRow(day: "2026-11-25", spend: ["naming": Spend(usd: 0.125)]),
        ]
        let spend = try #require(try report(days: days).spend)
        let tokyo = try #require(try report(days: days, now: "2026-12-31T20:00:00Z", zone: "Asia/Tokyo").spend)

        #expect(spend.thisYear == 1.375)
        #expect(spend.allTime == 5.875)
        #expect(tokyo.thisYear == 0)
        #expect(tokyo.allTime == 5.875)
    }

    @Test func perRecordedHourIsEveryMeetingRowsCostOverItsHoursFromOneHour() throws {
        func costing(_ seconds: Double, _ costs: MeetingRow.Costs) -> MeetingRow {
            MeetingRow(id: UUID(), at: "2026-03-02T09:00:00+00:00", duration: seconds, usd: costs)
        }
        let day = DayRow(day: "2026-03-02", spend: ["meeting": Spend(usd: 1)])
        let rows = [
            costing(5_370, MeetingRow.Costs(meeting: 1, summary: 0.25, naming: 0.25)),
            costing(1_800, MeetingRow.Costs(meeting: 0.375)),
            // Under a minute: its time and cost still count.
            costing(30, MeetingRow.Costs(meeting: 0.125)),
        ]

        #expect(try #require(try report(meetings: [costing(3_599, MeetingRow.Costs(meeting: 1))], days: [day]).spend).perRecordedHour == nil)
        #expect(try #require(try report(meetings: [costing(3_600, MeetingRow.Costs(meeting: 0.5))], days: [day]).spend).perRecordedHour == 0.5)
        #expect(try #require(try report(meetings: rows, days: [day]).spend).perRecordedHour == 1)
    }

    // MARK: - Dictation

    @Test func dictationAppearsAtTwentyDelivered() throws {
        let undelivered = DayRow(day: "2026-03-01", undelivered: ["silent": 40])

        #expect(try report(days: [undelivered, DayRow(day: "2026-03-02", delivered: 19)]).dictation == nil)
        #expect(try report(days: [
            undelivered, DayRow(day: "2026-03-02", delivered: 12), DayRow(day: "2026-03-03", delivered: 8),
        ]).dictation != nil)
    }

    // 1,800 timed words in 15 minutes take 45 minutes to type at 40 words a minute.
    @Test(arguments: [(40, 1_800.0), (60, 900.0), (120, 0.0), (200, 0.0)])
    func timeSavedIsTypingTheTimedWordsLessSayingThem(_ wpm: Int, _ saved: TimeInterval) throws {
        let dictation = try #require(try report(days: [
            DayRow(day: "2026-03-02", delivered: 12, words: 1_500, seconds: 600, timedWords: 1_200),
            DayRow(day: "2026-03-03", delivered: 10, words: 900, seconds: 300, timedWords: 600),
        ], typingWPM: wpm).dictation)

        #expect(dictation.words == 2_400)
        #expect(dictation.savedTyping == saved)
        #expect(dictation.typingWPM == wpm)
        #expect(dictation.wordsPerMinute == 120)
    }

    @Test func withoutTimedSpeechThereIsNoPace() throws {
        let dictation = try #require(try report(days: [DayRow(day: "2026-03-02", delivered: 20, words: 300)]).dictation)

        #expect(dictation.words == 300)
        #expect(dictation.savedTyping == 0)
        #expect(dictation.wordsPerMinute == nil)
    }

    // Of equal counts, the app named first.
    @Test func theTopFiveAppsLeaveOutOther() throws {
        let dictation = try #require(try report(days: [
            DayRow(day: "2026-03-02", delivered: 30, apps: ["other": 30]),
            DayRow(day: "2026-03-03", delivered: 23, apps: ["com.a": 10, "com.b": 3, "com.f": 5, "com.e": 5]),
            DayRow(day: "2026-03-04", delivered: 20, apps: ["com.b": 5, "com.c": 7, "com.d": 6, "other": 2]),
        ]).dictation)

        #expect(dictation.apps.map(\.bundleID) == ["com.a", "com.b", "com.c", "com.d", "com.e"])
        #expect(dictation.apps.map(\.count) == [10, 8, 7, 6, 5])
    }

    @Test func theTypicalAndLongestDictationComeFromDeliveredRows() throws {
        func row(_ words: Int, _ outcome: DictationAttempt.Outcome = .delivered) -> DictationRow {
            DictationRow(id: UUID().uuidString, at: "2026-03-02T09:00:00+00:00", words: words, outcome: outcome)
        }
        let days = [DayRow(day: "2026-03-02", delivered: 20)]

        let even = try #require(try report(
            days: days, dictations: [row(40), row(10), row(999, .failed), row(50), row(30), row(2_000, .superseded)]
        ).dictation)
        let odd = try #require(try report(days: days, dictations: [row(40), row(10), row(30)]).dictation)
        let pruned = try #require(try report(days: days, dictations: [row(70, .tooShort)]).dictation)

        #expect(even.typical == 35)
        #expect(even.longest == 50)
        #expect(odd.typical == 30)
        #expect(odd.longest == 40)
        #expect(pruned.typical == nil)
        #expect(pruned.longest == nil)
    }

    // MARK: - Records

    private func speakers(_ count: Int) -> [MeetingRow.Speaker] {
        (0..<count).map { MeetingRow.Speaker(id: $0, seconds: 10) }
    }

    @Test func recordsAppearAtThreeCountedMeetings() throws {
        let short = meeting("2026-03-05T09:00:00+00:00", seconds: 59)

        #expect(try report(meetings: filler(2) + [short]).records == nil)
        #expect(try report(meetings: filler(3) + [short]).records != nil)
    }

    @Test func theLongestMeetingCarriesItsIdAndWhetherItIsKept() throws {
        let kept = meeting("2026-03-02T09:00:00+00:00", seconds: 7_200)
        // 4 March in UTC.
        let deleted = meeting("2026-03-03T23:30:00-05:00", seconds: 9_000)
        let entry = TimelineInputs.KeptMeeting(title: "Planning", start: Date(timeIntervalSince1970: 1_772_442_000))

        let first = try #require(try report(meetings: filler(2) + [kept], kept: [kept.id: entry]).records?.longestMeeting)
        let second = try #require(try report(meetings: filler(2) + [kept, deleted], kept: [kept.id: entry]).records?.longestMeeting)

        #expect(first.id == kept.id)
        #expect(first.amount == 7_200)
        #expect(first.day == "2026-03-02")
        #expect(first.meeting == entry)
        #expect(second.id == deleted.id)
        #expect(second.amount == 9_000)
        #expect(second.day == "2026-03-03")
        #expect(second.meeting == nil)
    }

    @Test func aTiedMeetingRecordGoesToTheLaterMeeting() throws {
        let earlier = MeetingRow(id: UUID(), at: "2026-03-02T09:00:00+00:00", duration: 3_600, speakers: speakers(4))
        let later = MeetingRow(id: UUID(), at: "2026-03-02T15:00:00+00:00", duration: 3_600, speakers: speakers(4))

        let records = try #require(try report(meetings: [later, earlier, meeting("2026-01-01T09:00:00+00:00")]).records)

        #expect(records.longestMeeting?.id == later.id)
        #expect(records.mostSpeakers?.id == later.id)
    }

    @Test func theBusiestDayHasTheMostCountedMeetingsThenHoursThenIsTheLater() throws {
        func on(_ day: String, _ durations: [Double]) -> [MeetingRow] {
            durations.enumerated().map { index, seconds in
                meeting("\(day)T\(10 + index):00:00+00:00", seconds: seconds)
            }
        }
        let meetings = on("2026-03-02", [1_200, 1_200, 1_200])
            + on("2026-03-03", [7_200, 7_200])
            + on("2026-03-04", [1_800, 1_800, 1_800, 30, 30])
            + on("2026-02-27", [1_800, 1_800, 1_800])

        let busiest = try #require(try report(meetings: meetings).records?.busiestDay)
        let tied = try #require(try report(meetings: meetings + on("2026-03-06", [2_700, 1_800, 900])).records?.busiestDay)

        #expect(busiest.day == "2026-03-04")
        #expect(busiest.meetings == 3)
        #expect(busiest.recorded == 5_400)
        #expect(tied.day == "2026-03-06")
    }

    @Test func mostWordsInADayAddsMeetingWordsByStartDayAndWordsDictated() throws {
        let meetings = [
            // 3 March in UTC.
            meeting("2026-03-02T23:30:00-05:00", words: 1_000),
            meeting("2026-03-03T09:00:00+00:00", words: 1_400),
            // Under a minute.
            meeting("2026-03-03T10:00:00+00:00", seconds: 30, words: 900),
            meeting("2026-03-04T09:00:00+00:00", words: 100),
        ]
        let dictated = DayRow(day: "2026-03-02", delivered: 3, words: 500)

        let most = try #require(try report(meetings: meetings, days: [dictated, DayRow(day: "2026-03-05", words: 1_499)]).records?.mostWords)
        let tied = try #require(try report(meetings: meetings, days: [dictated, DayRow(day: "2026-03-05", words: 1_500)]).records?.mostWords)

        #expect(most.day == "2026-03-02")
        #expect(most.words == 1_500)
        #expect(tied.day == "2026-03-05")
    }

    @Test func theLongestStreakAndTheMostSpeakers() throws {
        let crowded = MeetingRow(id: UUID(), at: "2026-03-10T09:00:00+00:00", duration: 600, speakers: speakers(5))
        let meetings = filler(3) + [
            crowded,
            MeetingRow(id: UUID(), at: "2026-03-11T09:00:00+00:00", duration: 600, speakers: speakers(3)),
            MeetingRow(id: UUID(), at: "2026-03-12T09:00:00+00:00", duration: 59, speakers: speakers(9)),
        ]

        let records = try #require(try report(meetings: meetings, days: [DayRow(day: "2026-03-09", delivered: 1)]).records)

        // Three days in January and three in March: the later.
        #expect(records.longestStreak == Streak(days: 3, first: "2026-03-09", last: "2026-03-11"))
        #expect(records.mostSpeakers?.id == crowded.id)
        #expect(records.mostSpeakers?.amount == 5)
        #expect(records.mostSpeakers?.day == "2026-03-10")
        #expect(records.mostSpeakers?.meeting == nil)
        #expect(try report(meetings: filler(3)).records?.mostSpeakers == nil)
    }

    @Test func theNextMilestonesOfMeetingsHoursAndDictations() throws {
        let meetings = (1...3).map { meeting(String(format: "2026-01-%02dT09:00:00+00:00", $0), seconds: 5_400) }

        let records = try #require(try report(meetings: meetings).records)
        let exhausted = try #require(try report(meetings: meetings, days: [DayRow(day: "2026-02-01", delivered: 10_000)]).records)

        #expect(records.next == [
            NextMilestone(ladder: .meetings, step: 10, total: 3),
            NextMilestone(ladder: .hours, step: 10, total: 4.5),
            NextMilestone(ladder: .dictations, step: 1, total: 0),
        ])
        #expect(exhausted.next.map(\.ladder) == [.meetings, .hours])
    }

    // MARK: - Milestones

    @Test func milestonesAppearAtOneReached() throws {
        let short = meeting("2026-03-02T09:00:00+00:00", seconds: 59)

        #expect(try report(meetings: [short], days: [DayRow(day: "2026-03-02", words: 9_999)]).milestones == nil)
        #expect(try report(meetings: [short, meeting("2026-03-03T09:00:00+00:00")]).milestones == [
            Milestone(ladder: .meetings, value: 1, day: "2026-03-03"),
        ])
    }

    @Test func milestonesAreTheEightLatestOldestFirst() throws {
        let meetings = (1...25).map { meeting(String(format: "2026-01-%02dT09:00:00+00:00", $0), seconds: 3_600) }

        let result = try report(meetings: meetings, days: [DayRow(day: "2026-02-01", delivered: 100)])

        #expect(result.milestones == [
            Milestone(ladder: .hours, value: 1, day: "2026-01-01"),
            Milestone(ladder: .streak, value: 7, day: "2026-01-07"),
            Milestone(ladder: .meetings, value: 10, day: "2026-01-10"),
            Milestone(ladder: .hours, value: 10, day: "2026-01-10"),
            Milestone(ladder: .meetings, value: 25, day: "2026-01-25"),
            Milestone(ladder: .hours, value: 25, day: "2026-01-25"),
            Milestone(ladder: .dictations, value: 1, day: "2026-02-01"),
            Milestone(ladder: .dictations, value: 100, day: "2026-02-01"),
        ])
    }
}
