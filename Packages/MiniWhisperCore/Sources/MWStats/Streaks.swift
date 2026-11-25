import Foundation

/// A run of consecutive active days.
public struct Streak: Sendable, Equatable {
    public var days: Int
    /// Local `yyyy-MM-dd` of its first and last day.
    public var first: String
    public var last: String

    public init(days: Int, first: String, last: String) {
        self.days = days
        self.first = first
        self.last = last
    }
}

/// Active days and their streaks. A local day is active with at least one counted meeting, on its
/// start day at its own offset, or one delivered dictation.
public struct Streaks: Sendable, Equatable {
    /// Local `yyyy-MM-dd`, oldest first.
    public let activeDays: [String]
    /// Every streak, oldest first.
    public let runs: [Streak]
    /// The same streaks cut at each year end.
    private let yearRuns: [Streak]

    public init(_ snapshot: StatsSnapshot) {
        var active = Set(snapshot.days.lazy.filter { $0.delivered > 0 }.map(\.day))
        for row in snapshot.meetings where row.isCounted {
            if let day = row.startDay { active.insert(day) }
        }
        activeDays = active.sorted()

        var runs: [Streak] = []
        var yearRuns: [Streak] = []
        for day in activeDays {
            let fresh = Streak(days: 1, first: day, last: day)
            guard let previous = runs.last?.last, Self.day(1, after: previous) == day else {
                runs.append(fresh)
                yearRuns.append(fresh)
                continue
            }
            runs[runs.count - 1].extend(to: day)
            if Self.year(previous) == Self.year(day) {
                yearRuns[yearRuns.count - 1].extend(to: day)
            } else {
                yearRuns.append(fresh)
            }
        }
        self.runs = runs
        self.yearRuns = yearRuns
    }

    /// The longest streak; of equal ones, the later, as for every record.
    public var longest: Streak? { Self.longest(runs) }

    /// The longest streak counting only `year`'s days.
    public func longest(in year: Int) -> Streak? {
        Self.longest(yearRuns.filter { Self.year($0.first) == year })
    }

    public func activeDays(in year: Int) -> Int {
        activeDays.count { Self.year($0) == year }
    }

    /// The day `count` days after `key`, counted on the calendar so no day is skipped or repeated.
    static func day(_ count: Int, after key: String) -> String? {
        guard let start = StatsTime.date(ofDay: key),
              let date = StatsTime.utc.date(byAdding: .day, value: count, to: start)
        else { return nil }
        return StatsTime.dayKey(date, calendar: StatsTime.utc)
    }

    private static func year(_ key: String) -> Int? { Int(key.prefix(4)) }

    private static func longest(_ runs: [Streak]) -> Streak? {
        runs.reduce(nil) { best, run in run.days >= (best?.days ?? 0) ? run : best }
    }
}

private extension Streak {
    mutating func extend(to day: String) {
        days += 1
        last = day
    }
}
