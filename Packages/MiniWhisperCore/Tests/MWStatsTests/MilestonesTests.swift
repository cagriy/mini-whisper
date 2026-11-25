import Foundation
import Testing

import MWStats

@Suite struct MilestonesTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The local day `index` days after 1 January 2026.
    private func day(_ index: Int) -> String {
        let start = Self.utc.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        return StatsTime.dayKey(Self.utc.date(byAdding: .day, value: index, to: start)!, calendar: Self.utc)
    }

    private func meeting(_ day: String, duration: Double = 1_800, words: Int = 0) -> MeetingRow {
        MeetingRow(id: UUID(), at: "\(day)T09:00:00+00:00", duration: duration, words: words)
    }

    private func milestones(meetings: [MeetingRow] = [], days: [DayRow] = []) -> Milestones {
        let snapshot = StatsSnapshot(days: days, meetings: meetings)
        return Milestones(snapshot, streaks: Streaks(snapshot))
    }

    private func reached(_ result: Milestones, on ladder: Milestone.Ladder) -> [Milestone] {
        result.reached.filter { $0.ladder == ladder }
    }

    /// For each step, a day that brings the running total to one below it and the next day, which
    /// adds one and reaches it.
    private struct Rung {
        var belowDay: String
        var below: Int
        var day: String
    }

    private func climb(_ steps: [Int]) -> [Rung] {
        var total = 0
        return steps.enumerated().map { index, step in
            defer { total = step }
            return Rung(belowDay: day(2 * index), below: step - 1 - total, day: day(2 * index + 1))
        }
    }

    @Test func meetingsAreDatedOnTheDayTheirCountFirstReachedEachStep() {
        let steps = [1, 10, 25, 50, 100, 250, 500, 1_000]
        let rungs = climb(steps)
        let meetings = rungs.flatMap { rung in
            Array(repeating: rung.belowDay, count: rung.below).map { meeting($0) } + [meeting(rung.day)]
        }

        let result = milestones(meetings: meetings)

        #expect(reached(result, on: .meetings) == zip(steps, rungs).map {
            Milestone(ladder: .meetings, value: $0, day: $1.day)
        })
    }

    @Test func hoursAreDatedOnTheDayTheirTotalFirstReachedEachStep() {
        let steps = [1, 10, 25, 50, 100, 250, 500, 1_000]
        let rungs = climb(steps.map { $0 * 60 })
        let meetings = rungs.flatMap { rung in
            (rung.below > 0 ? [meeting(rung.belowDay, duration: Double(rung.below) * 60)] : [])
                + [meeting(rung.day, duration: 60)]
        }

        let result = milestones(meetings: meetings)

        #expect(reached(result, on: .hours) == zip(steps, rungs).map {
            Milestone(ladder: .hours, value: $0, day: $1.day)
        })
    }

    @Test func wordsTranscribedPlusDictatedAreDatedOnTheDayTheyFirstReachedEachStep() {
        let steps = [10_000, 50_000, 100_000, 250_000, 500_000, 1_000_000]
        let rungs = climb(steps)

        let result = milestones(
            meetings: rungs.map { meeting($0.day, words: 1) },
            days: rungs.map { DayRow(day: $0.belowDay, words: $0.below) }
        )

        #expect(reached(result, on: .words) == zip(steps, rungs).map {
            Milestone(ladder: .words, value: $0, day: $1.day)
        })
    }

    @Test func dictationsAreDatedOnTheDayTheirCountFirstReachedEachStep() {
        let steps = [1, 100, 500, 1_000, 5_000, 10_000]
        let rungs = climb(steps)
        let days = rungs.flatMap { rung in
            (rung.below > 0 ? [DayRow(day: rung.belowDay, delivered: rung.below)] : [])
                + [DayRow(day: rung.day, delivered: 1)]
        }

        let result = milestones(days: days)

        #expect(reached(result, on: .dictations) == zip(steps, rungs).map {
            Milestone(ladder: .dictations, value: $0, day: $1.day)
        })
    }

    @Test func aStreakStepIsDatedOnTheDayAStreakFirstReachedIt() {
        let early = (0..<6).map { DayRow(day: day($0), delivered: 1) }
        let long = (10..<110).map { DayRow(day: day($0), delivered: 1) }

        let result = milestones(days: early + long)

        #expect(reached(result, on: .streak) == [
            Milestone(ladder: .streak, value: 7, day: "2026-01-17"),
            Milestone(ladder: .streak, value: 30, day: "2026-02-09"),
            Milestone(ladder: .streak, value: 100, day: "2026-04-20"),
        ])
    }

    @Test func onlyCountedMeetingsCount() {
        let short = (0..<3).map { _ in meeting(day(0), duration: 59, words: 20_000) }

        let result = milestones(meetings: short)

        #expect(result.reached.isEmpty)
        #expect(result.next(.meetings) == NextMilestone(ladder: .meetings, step: 1, total: 0))
        #expect(result.next(.words) == NextMilestone(ladder: .words, step: 10_000, total: 0))
    }

    @Test func aMeetingCountsOnItsLocalStartDayAtItsOwnOffset() {
        let result = milestones(meetings: [MeetingRow(id: UUID(), at: "2026-12-31T23:30:00-05:00", duration: 3_600)])

        #expect(result.reached == [
            Milestone(ladder: .meetings, value: 1, day: "2026-12-31"),
            Milestone(ladder: .hours, value: 1, day: "2026-12-31"),
        ])
    }

    @Test func milestonesOfOneDayOrderByLadderThenValue() {
        let warmUp = (0..<6).map { DayRow(day: day($0), delivered: 1) }
        let big = (0..<12).map { _ in meeting(day(6), duration: 3_600, words: 1_000) }

        let result = milestones(meetings: big, days: warmUp + [DayRow(day: day(6), delivered: 94)])

        #expect(result.reached.filter { $0.day == day(6) } == [
            Milestone(ladder: .meetings, value: 1, day: day(6)),
            Milestone(ladder: .meetings, value: 10, day: day(6)),
            Milestone(ladder: .hours, value: 1, day: day(6)),
            Milestone(ladder: .hours, value: 10, day: day(6)),
            Milestone(ladder: .words, value: 10_000, day: day(6)),
            Milestone(ladder: .dictations, value: 100, day: day(6)),
            Milestone(ladder: .streak, value: 7, day: day(6)),
        ])
        #expect(result.reached.first == Milestone(ladder: .dictations, value: 1, day: day(0)))
    }

    @Test func theNextStepCarriesTheRunningTotal() throws {
        let result = milestones(
            meetings: (0..<3).map { meeting(day($0), duration: 5_400, words: 4_000) },
            days: [DayRow(day: day(5), delivered: 120)]
        )

        let hours = try #require(result.next(.hours))
        #expect(result.next(.meetings) == NextMilestone(ladder: .meetings, step: 10, total: 3))
        #expect(hours == NextMilestone(ladder: .hours, step: 10, total: 4.5))
        #expect(hours.fraction == 0.45)
        #expect(result.next(.dictations) == NextMilestone(ladder: .dictations, step: 500, total: 120))
        #expect(result.next(.words) == NextMilestone(ladder: .words, step: 50_000, total: 12_000))
        #expect(result.next(.streak) == NextMilestone(ladder: .streak, step: 7, total: 3))
    }

    @Test func aStepReachedExactlyMovesTheNextStepOn() {
        let result = milestones(
            meetings: (0..<10).map { _ in meeting(day(0)) },
            days: [DayRow(day: day(0), delivered: 9_999)]
        )

        #expect(result.next(.meetings) == NextMilestone(ladder: .meetings, step: 25, total: 10))
        #expect(result.next(.dictations) == NextMilestone(ladder: .dictations, step: 10_000, total: 9_999))
    }

    /// A record whose running total on `ladder` is `total`.
    private func milestones(_ ladder: Milestone.Ladder, total: Int) -> Milestones {
        switch ladder {
        case .meetings: milestones(meetings: (0..<total).map { _ in meeting(day(0)) })
        case .hours: milestones(meetings: [meeting(day(0), duration: Double(total) * 3_600)])
        case .words: milestones(meetings: [meeting(day(0), words: total)])
        case .dictations: milestones(days: [DayRow(day: day(0), delivered: total)])
        case .streak: milestones(days: (0..<total).map { DayRow(day: day($0), delivered: 1) })
        }
    }

    @Test(arguments: [
        (Milestone.Ladder.meetings, 1_000), (.hours, 1_000), (.words, 1_000_000), (.dictations, 10_000), (.streak, 100),
    ])
    func aLadderMetersItsLastStepUntilItIsExhausted(_ ladder: Milestone.Ladder, _ last: Int) {
        #expect(milestones(ladder, total: last - 1).next(ladder) == NextMilestone(ladder: ladder, step: last, total: Double(last - 1)))
        #expect(milestones(ladder, total: last).next(ladder) == nil)
    }

    @Test func theLatestEightRunOldestFirst() {
        let result = milestones(
            meetings: [meeting("2026-01-05", duration: 3_600)]
                + (0..<9).map { _ in meeting("2026-02-01", duration: 3_600) }
                + (0..<15).map { _ in meeting("2026-04-01", duration: 3_600) },
            days: [
                DayRow(day: "2026-03-01", delivered: 100, words: 10_000),
                DayRow(day: "2026-05-01", delivered: 400, words: 40_000),
            ]
        )

        #expect(result.reached.count == 11)
        #expect(result.latest == [
            Milestone(ladder: .hours, value: 10, day: "2026-02-01"),
            Milestone(ladder: .words, value: 10_000, day: "2026-03-01"),
            Milestone(ladder: .dictations, value: 1, day: "2026-03-01"),
            Milestone(ladder: .dictations, value: 100, day: "2026-03-01"),
            Milestone(ladder: .meetings, value: 25, day: "2026-04-01"),
            Milestone(ladder: .hours, value: 25, day: "2026-04-01"),
            Milestone(ladder: .words, value: 50_000, day: "2026-05-01"),
            Milestone(ladder: .dictations, value: 500, day: "2026-05-01"),
        ])
    }

    @Test func fewerThanEightAreAllLatest() {
        let result = milestones(meetings: [meeting("2026-01-05", duration: 3_600)])

        #expect(result.latest == result.reached)
        #expect(result.latest.count == 2)
    }
}
