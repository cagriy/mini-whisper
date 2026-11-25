import Foundation

/// What the Timeline report is computed from.
public struct TimelineInputs: Sendable {
    /// A meeting still stored, as the meeting index lists it.
    public struct KeptMeeting: Sendable, Equatable {
        public var title: String
        public var start: Date

        public init(title: String, start: Date) {
            self.title = title
            self.start = start
        }
    }

    public var snapshot: StatsSnapshot
    /// Kept meetings by id; a row whose id is missing belongs to a deleted meeting.
    public var kept: [UUID: KeptMeeting]
    public var typingWPM: Int
    public var now: Date
    /// Its time zone sets this year; its first weekday orders the grids' rows.
    public var calendar: Calendar

    public init(snapshot: StatsSnapshot, kept: [UUID: KeptMeeting], typingWPM: Int, now: Date, calendar: Calendar) {
        self.snapshot = snapshot
        self.kept = kept
        self.typingWPM = typingWPM
        self.now = now
        self.calendar = calendar
    }
}

/// Timeline's figures: one value a panel, nil below its threshold. Meetings under a minute count
/// in nothing but spend. Durations are seconds.
public struct TimelineReport: Sendable, Equatable {
    /// Calendar weekdays, 1 Sunday to 7 Saturday, in the order the grids' rows run.
    public let weekdays: [Int]
    /// From one counted meeting or one delivered dictation.
    public let totals: Totals?
    /// From one active day.
    public let year: Year?
    /// From ten counted meetings.
    public let rhythm: Rhythm?
    /// From three counted meetings with the user known.
    public let talkShare: TalkShare?

    /// A zero figure is nil, so it is left out.
    public struct Totals: Sendable, Equatable {
        public let meetings: Int?
        public let recorded: TimeInterval?
        public let wordsTranscribed: Int?
        public let dictations: Int?
        /// Estimated US dollars: every day's spend of every purpose.
        public let spend: Double?
    }

    public struct Year: Sendable, Equatable {
        /// From the earliest year with an active day to this year, oldest first.
        public let years: [CalendarYear]
    }

    public struct CalendarYear: Sendable, Equatable {
        public let year: Int
        /// Time recorded a day: under 1 h, under 2 h, under 4 h, then more.
        public let meetings: YearGrid
        /// Dictations delivered a day: 1–5, 6–15, 16–40, then more.
        public let dictation: YearGrid
        /// Days with a counted meeting or a delivered dictation.
        public let activeDays: Int
        /// Counting this year's days only.
        public let longestStreak: Streak?
        public let dictationDays: Int
    }

    /// Seven rows by 53 or 54 week columns.
    public struct YearGrid: Sendable, Equatable {
        /// Columns of seven in `weekdays` order; nil before 1 January and after 31 December.
        public let weeks: [[Day?]]
    }

    public struct Day: Sendable, Equatable {
        /// Local `yyyy-MM-dd`.
        public let key: String
        /// Seconds recorded, or dictations delivered.
        public let amount: Double
        /// 0 for none, then 1 to 4.
        public let level: Int
    }

    public struct Rhythm: Sendable, Equatable {
        /// Counted meetings by the local weekday and hour they started.
        public let meetings: RhythmGrid
        /// Delivered dictations by weekday and hour; from 50 delivered.
        public let dictation: RhythmGrid?
        /// Counted meetings starting 0 to 300 s after the previous counted meeting ended.
        public let backToBack: Int
        /// The earliest local time of day a counted meeting started, in seconds after midnight.
        public let earliestStart: TimeInterval?
        /// The latest local time of day one ended, in seconds after its start day's midnight, so an
        /// end on a later day reads past 24:00.
        public let latestFinish: TimeInterval?
    }

    public struct RhythmGrid: Sendable, Equatable {
        /// Seven rows in `weekdays` order of 24 hours.
        public let counts: [[Int]]
        /// 0 for none, then quarters of the largest cell.
        public let levels: [[Int]]
        /// The largest cell; of equal ones, the later in the grid.
        public let busiest: Slot?
    }

    public struct Slot: Sendable, Equatable {
        /// 1 Sunday to 7 Saturday.
        public let weekday: Int
        public let hour: Int

        public init(weekday: Int, hour: Int) {
            self.weekday = weekday
            self.hour = hour
        }
    }

    /// Over counted meetings with the user known.
    public struct TalkShare: Sendable, Equatable {
        public let meetings: Int
        /// Σ user seconds ÷ Σ speech.
        public let share: Double
        /// Σ user words ÷ Σ user minutes.
        public let wordsPerMinute: Double
        public let questions: Int
        /// The user's share in each of the last 20, oldest first.
        public let recent: [Double]
    }
}

public enum TimelineStats {
    public static func compute(_ inputs: TimelineInputs) -> TimelineReport {
        let snapshot = inputs.snapshot
        let week = Week(firstWeekday: inputs.calendar.firstWeekday)
        let meetings = MeetingPass(snapshot.meetings, week: week)
        let days = DayPass(snapshot.days, week: week)

        let totals = meetings.count > 0 || days.delivered > 0 ? TimelineReport.Totals(
            meetings: nonZero(meetings.count), recorded: nonZero(meetings.recorded),
            wordsTranscribed: nonZero(meetings.words), dictations: nonZero(days.delivered),
            spend: nonZero(days.spend)
        ) : nil

        let rhythm = meetings.count >= 10 ? TimelineReport.Rhythm(
            meetings: rhythmGrid(meetings.rhythm, week: week),
            dictation: days.delivered >= 50 ? rhythmGrid(days.rhythm, week: week) : nil,
            backToBack: meetings.backToBack, earliestStart: meetings.earliestStart,
            latestFinish: meetings.latestFinish
        ) : nil

        let talk = meetings.talk
        let talkShare = talk.count >= 3 ? TimelineReport.TalkShare(
            meetings: talk.count, share: ratio(talk.userSeconds, talk.speech),
            wordsPerMinute: ratio(Double(talk.userWords), talk.userSeconds / 60), questions: talk.questions,
            recent: talk.shares.sorted { $0.start < $1.start }.suffix(20).map(\.share)
        ) : nil

        return TimelineReport(
            weekdays: week.weekdays, totals: totals,
            year: theYear(snapshot, meetings: meetings, days: days, week: week, now: inputs.now, calendar: inputs.calendar),
            rhythm: rhythm, talkShare: talkShare
        )
    }

    // MARK: - The year

    private static func theYear(
        _ snapshot: StatsSnapshot, meetings: MeetingPass, days: DayPass, week: Week, now: Date, calendar: Calendar
    ) -> TimelineReport.Year? {
        let streaks = Streaks(snapshot)
        guard let first = streaks.activeDays.first.flatMap(year(of:)),
              let thisYear = year(of: StatsTime.dayKey(now, calendar: calendar))
        else { return nil }
        return TimelineReport.Year(years: (min(first, thisYear)...thisYear).map { year in
            let layout = YearLayout(year, week: week)
            return TimelineReport.CalendarYear(
                year: year,
                meetings: layout.grid { key in
                    let seconds = meetings.recordedByDay[key, default: 0]
                    return TimelineReport.Day(key: key, amount: seconds, level: level(recorded: seconds))
                },
                dictation: layout.grid { key in
                    let count = days.deliveredByDay[key, default: 0]
                    return TimelineReport.Day(key: key, amount: Double(count), level: level(delivered: count))
                },
                activeDays: streaks.activeDays(in: year), longestStreak: streaks.longest(in: year),
                dictationDays: days.dictationDays[year, default: 0]
            )
        })
    }

    private static func level(recorded seconds: TimeInterval) -> Int {
        seconds > 0 ? 1 + [3_600, 7_200, 14_400].count { seconds >= $0 } : 0
    }

    private static func level(delivered count: Int) -> Int {
        count > 0 ? 1 + [6, 16, 41].count { count >= $0 } : 0
    }

    /// The days of a year in week columns, 1 January in the row of its weekday.
    private struct YearLayout {
        let lead: Int
        let keys: [String]

        init(_ year: Int, week: Week) {
            keys = (1...12).flatMap { month -> [String] in
                guard let first = utc.date(from: DateComponents(year: year, month: month, day: 1)),
                      let days = utc.range(of: .day, in: .month, for: first)
                else { return [] }
                return days.map { String(format: "%04d-%02d-%02d", year, month, $0) }
            }
            lead = keys.first.flatMap(weekday(of:)).map(week.row(of:)) ?? 0
        }

        func grid(_ day: (String) -> TimelineReport.Day) -> TimelineReport.YearGrid {
            var weeks = [[TimelineReport.Day?]](
                repeating: Array(repeating: nil, count: 7), count: (lead + keys.count + 6) / 7
            )
            for (index, key) in keys.enumerated() {
                weeks[(lead + index) / 7][(lead + index) % 7] = day(key)
            }
            return TimelineReport.YearGrid(weeks: weeks)
        }
    }

    // MARK: - Weekly rhythm

    private static func rhythmGrid(_ counts: [[Int]], week: Week) -> TimelineReport.RhythmGrid {
        let largest = counts.joined().max() ?? 0
        var busiest: TimelineReport.Slot?
        for (row, hours) in counts.enumerated() {
            for (hour, count) in hours.enumerated() where count > 0 && count == largest {
                busiest = TimelineReport.Slot(weekday: week.weekdays[row], hour: hour)
            }
        }
        // A cell at exactly a quarter stays in the level below it.
        let levels = counts.map { $0.map { $0 > 0 ? (4 * $0 + largest - 1) / largest : 0 } }
        return TimelineReport.RhythmGrid(counts: counts, levels: levels, busiest: busiest)
    }

    // MARK: - Passes

    private struct Talk {
        var count = 0
        var userSeconds: TimeInterval = 0
        var userWords = 0
        var speech: TimeInterval = 0
        var questions = 0
        var shares: [(start: Date, share: Double)] = []
    }

    /// One pass over the counted meetings.
    private struct MeetingPass {
        var count = 0
        var recorded: TimeInterval = 0
        var words = 0
        var recordedByDay: [String: TimeInterval] = [:]
        var rhythm = Week.emptyGrid
        var earliestStart: TimeInterval?
        var latestFinish: TimeInterval?
        var backToBack = 0
        var talk = Talk()
        private var spans: [(start: Date, end: Date)] = []

        init(_ rows: [MeetingRow], week: Week) {
            for row in rows where row.isCounted {
                count += 1
                recorded += row.duration
                words += row.words
                if let day = row.startDay { recordedByDay[day, default: 0] += row.duration }
                if let start = row.localStart { add(start: start, end: row.localEnd, week: week) }
                if row.userKnown { add(talkOf: row) }
            }
            spans.sort { $0.start < $1.start }
            backToBack = zip(spans, spans.dropFirst()).count { previous, next in
                (0...300).contains(next.start.timeIntervalSince(previous.end))
            }
        }

        private mutating func add(start: DateComponents, end: DateComponents?, week: Week) {
            if let weekday = start.weekday, let hour = start.hour { rhythm[week.row(of: weekday)][hour] += 1 }
            earliestStart = min(earliestStart ?? .infinity, timeOfDay(start))
            guard let end else { return }
            if let from = start.date, let to = end.date { spans.append((from, to)) }
            if let days = dayCount(from: start, to: end) {
                latestFinish = max(latestFinish ?? -.infinity, Double(days * 24 * 3_600) + timeOfDay(end))
            }
        }

        private mutating func add(talkOf row: MeetingRow) {
            let user = row.speakers.first { $0.id == row.user }
            let seconds = user?.seconds ?? 0
            talk.count += 1
            talk.userSeconds += seconds
            talk.userWords += user?.words ?? 0
            talk.speech += row.speech
            talk.questions += user?.questions ?? 0
            talk.shares.append((row.localStart?.date ?? .distantPast, ratio(seconds, row.speech)))
        }
    }

    /// One pass over the day rows.
    private struct DayPass {
        var delivered = 0
        var spend: Double = 0
        var deliveredByDay: [String: Int] = [:]
        var dictationDays: [Int: Int] = [:]
        var rhythm = Week.emptyGrid

        init(_ rows: [DayRow], week: Week) {
            for row in rows {
                spend += row.spend.values.reduce(0) { $0 + $1.usd }
                guard row.delivered > 0 else { continue }
                delivered += row.delivered
                deliveredByDay[row.day, default: 0] += row.delivered
                if let year = year(of: row.day) { dictationDays[year, default: 0] += 1 }
                guard let weekday = weekday(of: row.day) else { continue }
                let weekRow = week.row(of: weekday)
                for (key, count) in row.hours {
                    if let hour = Int(key), (0..<24).contains(hour) { rhythm[weekRow][hour] += count }
                }
            }
        }
    }

    // MARK: - Time

    /// Rows of the grids, from the calendar's first weekday.
    private struct Week {
        let firstWeekday: Int
        let weekdays: [Int]

        static let emptyGrid = Array(repeating: Array(repeating: 0, count: 24), count: 7)

        init(firstWeekday: Int) {
            self.firstWeekday = firstWeekday
            weekdays = (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
        }

        func row(of weekday: Int) -> Int { (weekday - firstWeekday + 7) % 7 }
    }

    /// Day keys are Gregorian dates, so their weekdays and lengths come from `StatsTime.utc`.
    private static var utc: Calendar { StatsTime.utc }

    private static func year(of key: String) -> Int? { Int(key.prefix(4)) }

    private static func weekday(of key: String) -> Int? {
        StatsTime.date(ofDay: key).map { utc.component(.weekday, from: $0) }
    }

    private static func timeOfDay(_ clock: DateComponents) -> TimeInterval {
        Double((clock.hour ?? 0) * 3_600 + (clock.minute ?? 0) * 60 + (clock.second ?? 0))
    }

    /// Local days from one wall clock's date to another's.
    private static func dayCount(from start: DateComponents, to end: DateComponents) -> Int? {
        guard let from = utc.date(from: DateComponents(year: start.year, month: start.month, day: start.day)),
              let to = utc.date(from: DateComponents(year: end.year, month: end.month, day: end.day))
        else { return nil }
        return utc.dateComponents([.day], from: from, to: to).day
    }

    // MARK: - Numbers

    private static func nonZero<Value: AdditiveArithmetic>(_ value: Value) -> Value? {
        value == .zero ? nil : value
    }

    /// Zero when there is nothing to divide by.
    private static func ratio(_ part: Double, _ whole: Double) -> Double {
        whole > 0 ? part / whole : 0
    }
}
