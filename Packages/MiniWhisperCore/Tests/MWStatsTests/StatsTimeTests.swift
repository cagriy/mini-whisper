import Foundation
import Testing

import MWStats

@Suite struct StatsTimeTests {
    private func utc(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    // London changes clock at 01:00 UTC on 2026-03-29 and 2026-10-25: the same UTC time of day
    // lands on a different local day and hour either side.
    @Test(arguments: [
        ("2026-03-28T23:30:00Z", "2026-03-28", 23),
        ("2026-03-29T23:30:00Z", "2026-03-30", 0),
        ("2026-10-24T23:30:00Z", "2026-10-25", 0),
        ("2026-10-25T23:30:00Z", "2026-10-25", 23),
    ])
    func dayAndHourFollowTheClockAcrossDSTChanges(_ instant: String, _ day: String, _ hour: Int) throws {
        let london = try calendar("Europe/London")
        let date = try utc(instant)

        #expect(StatsTime.dayKey(date, calendar: london) == day)
        #expect(StatsTime.hour(date, calendar: london) == hour)
    }

    @Test func oneInstantFallsOnTwoDaysInTwoTimeZones() throws {
        let date = try utc("2026-11-30T23:30:00Z")

        #expect(StatsTime.dayKey(date, calendar: try calendar("UTC")) == "2026-11-30")
        #expect(StatsTime.dayKey(date, calendar: try calendar("Asia/Kolkata")) == "2026-12-01")
    }

    @Test func dayKeysAreGregorianWhateverTheCalendar() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = try #require(TimeZone(identifier: "UTC"))

        #expect(StatsTime.dayKey(try utc("2026-11-30T09:14:03Z"), calendar: buddhist) == "2026-11-30")
    }

    @Test(arguments: [
        ("UTC", "2026-11-30T09:14:03+00:00"),
        ("Asia/Kolkata", "2026-11-30T14:44:03+05:30"),
        ("America/Los_Angeles", "2026-11-30T01:14:03-08:00"),
    ])
    func isoWritesWholeSecondsOfLocalTimeWithItsOffset(_ zone: String, _ expected: String) throws {
        let date = try utc("2026-11-30T09:14:03Z").addingTimeInterval(0.75)

        #expect(StatsTime.iso(date, timeZone: try #require(TimeZone(identifier: zone))) == expected)
    }

    @Test(arguments: ["UTC", "Asia/Kolkata", "America/Los_Angeles"])
    func parseRoundTripsTheInstantAndOffset(_ zone: String) throws {
        let timeZone = try #require(TimeZone(identifier: zone))
        let date = try utc("2026-11-30T09:14:03Z")

        let parsed = try #require(StatsTime.parse(StatsTime.iso(date, timeZone: timeZone)))

        #expect(parsed.date == date)
        #expect(parsed.offset == timeZone.secondsFromGMT(for: date))
    }

    @Test func parseReadsAnOffsetAndRejectsOtherShapes() throws {
        let parsed = try #require(StatsTime.parse("2026-11-30T14:44:03+05:30"))

        #expect(parsed.date == (try utc("2026-11-30T09:14:03Z")))
        #expect(parsed.offset == 19_800)
        #expect(StatsTime.parse("2026-11-30") == nil)
        #expect(StatsTime.parse("2026-11-30T14:44:03") == nil)
        #expect(StatsTime.parse("2026-11-30T14:44:03+05:3x") == nil)
    }

    @Test(arguments: [
        ("2026-11-24T15:00:00Z", "2025-10-23T23:00:00Z"),
        ("2026-03-31T10:00:00Z", "2025-02-28T00:00:00Z"),
    ])
    func dictationCutoffIsTheStartOfTheLocalDayThirteenMonthsBack(_ now: String, _ cutoff: String) throws {
        let london = try calendar("Europe/London")

        #expect(StatsTime.dictationCutoff(now: try utc(now), calendar: london) == (try utc(cutoff)))
    }
}
