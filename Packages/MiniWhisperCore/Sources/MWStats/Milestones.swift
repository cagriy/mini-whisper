import Foundation

/// A step of a ladder and the local day the running total first reached it.
public struct Milestone: Sendable, Equatable {
    /// Ladders in the order milestones of one day are listed.
    public enum Ladder: Int, Sendable, CaseIterable {
        /// Counted meetings.
        case meetings
        /// Recorded hours of counted meetings.
        case hours
        /// Words transcribed in counted meetings plus words dictated.
        case words
        /// Delivered dictations.
        case dictations
        /// Days in the longest streak.
        case streak

        var steps: [Int] {
            switch self {
            case .meetings, .hours: [1, 10, 25, 50, 100, 250, 500, 1_000]
            case .words: [10_000, 50_000, 100_000, 250_000, 500_000, 1_000_000]
            case .dictations: [1, 100, 500, 1_000, 5_000, 10_000]
            case .streak: [7, 30, 100]
            }
        }

        /// Hours run in seconds, so whole-hour steps compare without rounding.
        var scale: Double { self == .hours ? 3_600 : 1 }
    }

    public var ladder: Ladder
    public var value: Int
    /// Local `yyyy-MM-dd`.
    public var day: String

    public init(ladder: Ladder, value: Int, day: String) {
        self.ladder = ladder
        self.value = value
        self.day = day
    }
}

/// The next step of a ladder and how far the running total has come.
public struct NextMilestone: Sendable, Equatable {
    public var ladder: Milestone.Ladder
    public var step: Int
    /// In the ladder's unit: hours for `.hours`, days for `.streak`.
    public var total: Double

    public init(ladder: Milestone.Ladder, step: Int, total: Double) {
        self.ladder = ladder
        self.step = step
        self.total = total
    }

    public var fraction: Double { total / Double(step) }
}

/// Every milestone reached, from the record's days in order. A meeting counts on its local start
/// day at its own offset; only counted meetings count.
public struct Milestones: Sendable, Equatable {
    /// Oldest first; one day's milestones by ladder, then value.
    public let reached: [Milestone]
    /// Running totals now, in `Ladder.scale` units.
    private let totals: [Milestone.Ladder: Double]

    /// `streaks` must be of the same snapshot.
    public init(_ snapshot: StatsSnapshot, streaks: Streaks) {
        var days: [String: [Milestone.Ladder: Double]] = [:]
        for row in snapshot.meetings where row.isCounted {
            guard let day = row.startDay else { continue }
            days[day, default: [:]].merge([.meetings: 1, .hours: row.duration, .words: Double(row.words)], uniquingKeysWith: +)
        }
        for row in snapshot.days {
            days[row.day, default: [:]].merge([.words: Double(row.words), .dictations: Double(row.delivered)], uniquingKeysWith: +)
        }

        var reached: [Milestone] = []
        var totals: [Milestone.Ladder: Double] = [:]
        for (day, amounts) in days.sorted(by: { $0.key < $1.key }) {
            for (ladder, amount) in amounts {
                let before = totals[ladder, default: 0]
                let after = before + amount
                totals[ladder] = after
                for step in ladder.steps {
                    let target = Double(step) * ladder.scale
                    if before < target, target <= after {
                        reached.append(Milestone(ladder: ladder, value: step, day: day))
                    }
                }
            }
        }

        // The first streak to reach a step reaches it on its step-th day.
        for step in Milestone.Ladder.streak.steps {
            guard let run = streaks.runs.first(where: { $0.days >= step }),
                  let day = Streaks.day(step - 1, after: run.first)
            else { break }
            reached.append(Milestone(ladder: .streak, value: step, day: day))
        }
        totals[.streak] = Double(streaks.longest?.days ?? 0)

        self.reached = reached.sorted {
            ($0.day, $0.ladder.rawValue, $0.value) < ($1.day, $1.ladder.rawValue, $1.value)
        }
        self.totals = totals
    }

    /// The eight latest reached, oldest first.
    public var latest: [Milestone] { Array(reached.suffix(8)) }

    /// Nil once every step of the ladder is reached.
    public func next(_ ladder: Milestone.Ladder) -> NextMilestone? {
        let total = totals[ladder, default: 0]
        guard let step = ladder.steps.first(where: { Double($0) * ladder.scale > total }) else { return nil }
        return NextMilestone(ladder: ladder, step: step, total: total / ladder.scale)
    }
}
