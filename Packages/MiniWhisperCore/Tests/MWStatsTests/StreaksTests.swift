import Foundation
import Testing

import MWStats

@Suite struct StreaksTests {
    private func meeting(_ at: String, duration: Double = 1_800) -> MeetingRow {
        MeetingRow(id: UUID(), at: at, duration: duration)
    }

    private func dictated(_ day: String, delivered: Int = 1) -> DayRow {
        DayRow(day: day, delivered: delivered, words: 12 * delivered)
    }

    private func streaks(meetings: [MeetingRow] = [], days: [DayRow] = []) -> Streaks {
        Streaks(StatsSnapshot(days: days, meetings: meetings))
    }

    @Test func activeDaysHaveACountedMeetingOrADeliveredDictation() {
        let result = streaks(
            meetings: [
                meeting("2026-03-02T09:00:00+00:00"),
                meeting("2026-03-04T09:00:00+00:00", duration: 59),
                meeting("", duration: 3_600),
            ],
            days: [
                dictated("2026-03-03"),
                DayRow(day: "2026-03-05", undelivered: ["too_short": 2]),
                DayRow(day: "2026-03-06", spend: ["meeting": Spend(usd: 0.4)]),
                dictated("2026-03-02", delivered: 3),
            ]
        )

        #expect(result.activeDays == ["2026-03-02", "2026-03-03"])
    }

    @Test func aMeetingIsActiveOnItsLocalStartDayAtItsOwnOffset() {
        let result = streaks(meetings: [
            meeting("2026-12-31T23:30:00-05:00"),
            meeting("2027-01-02T00:30:00+09:00"),
        ])

        #expect(result.activeDays == ["2026-12-31", "2027-01-02"])
    }

    @Test func theLongestStreakCarriesItsFirstAndLastDay() {
        let result = streaks(
            meetings: [meeting("2026-05-10T09:00:00+00:00"), meeting("2026-05-12T15:00:00+00:00")],
            days: [
                dictated("2026-05-01"), dictated("2026-05-02"),
                dictated("2026-05-11"), dictated("2026-05-13"),
            ]
        )

        #expect(result.longest == Streak(days: 4, first: "2026-05-10", last: "2026-05-13"))
        #expect(result.runs == [
            Streak(days: 2, first: "2026-05-01", last: "2026-05-02"),
            Streak(days: 4, first: "2026-05-10", last: "2026-05-13"),
        ])
    }

    @Test func aGapDayBreaksTheStreak() {
        let result = streaks(days: ["2026-06-01", "2026-06-02", "2026-06-04", "2026-06-05", "2026-06-06"].map { dictated($0) })

        #expect(result.longest == Streak(days: 3, first: "2026-06-04", last: "2026-06-06"))
        #expect(result.runs.map(\.days) == [2, 3])
    }

    @Test func consecutiveDaysCrossMonthEndsAndALeapDay() {
        let result = streaks(days: ["2028-01-31", "2028-02-01", "2028-02-28", "2028-02-29", "2028-03-01"].map { dictated($0) })

        #expect(result.runs.map(\.days) == [2, 3])
    }

    @Test func ofEqualStreaksTheLaterIsTheLongest() {
        let result = streaks(days: ["2026-07-01", "2026-07-02", "2026-07-08", "2026-07-09"].map { dictated($0) })

        #expect(result.longest == Streak(days: 2, first: "2026-07-08", last: "2026-07-09"))
    }

    @Test func aStreakAcrossAYearEndCountsOnlyThatYearsDaysWithinAYear() {
        let result = streaks(
            meetings: [meeting("2026-12-30T10:00:00+00:00"), meeting("2027-01-02T10:00:00+00:00")],
            days: [dictated("2026-12-31"), dictated("2027-01-01")]
        )

        #expect(result.longest == Streak(days: 4, first: "2026-12-30", last: "2027-01-02"))
        #expect(result.longest(in: 2026) == Streak(days: 2, first: "2026-12-30", last: "2026-12-31"))
        #expect(result.longest(in: 2027) == Streak(days: 2, first: "2027-01-01", last: "2027-01-02"))
    }

    @Test func withinAYearTheLongestMayDifferFromOverall() {
        let result = streaks(days: [
            "2026-03-01", "2026-03-02", "2026-03-03",
            "2026-12-31", "2027-01-01", "2027-01-02", "2027-01-03",
        ].map { dictated($0) })

        #expect(result.longest?.days == 4)
        #expect(result.longest(in: 2026) == Streak(days: 3, first: "2026-03-01", last: "2026-03-03"))
        #expect(result.longest(in: 2027) == Streak(days: 3, first: "2027-01-01", last: "2027-01-03"))
        #expect(result.longest(in: 2025) == nil)
    }

    @Test func activeDaysAreCountedPerYear() {
        let result = streaks(days: ["2026-12-30", "2026-12-31", "2027-01-01", "2027-02-14", "2027-06-01"].map { dictated($0) })

        #expect(result.activeDays(in: 2026) == 2)
        #expect(result.activeDays(in: 2027) == 3)
        #expect(result.activeDays(in: 2028) == 0)
    }

    @Test func noActiveDayMeansNoStreakAndOneMeansADay() {
        let short = meeting("2026-03-02T09:00:00+00:00", duration: 30)
        let none = streaks(meetings: [short])
        let one = streaks(meetings: [short], days: [dictated("2026-03-02")])

        #expect(none.activeDays.isEmpty)
        #expect(none.runs.isEmpty)
        #expect(none.longest == nil)
        #expect(none.longest(in: 2026) == nil)
        #expect(one.longest == Streak(days: 1, first: "2026-03-02", last: "2026-03-02"))
        #expect(one.longest(in: 2026) == one.longest)
    }
}
