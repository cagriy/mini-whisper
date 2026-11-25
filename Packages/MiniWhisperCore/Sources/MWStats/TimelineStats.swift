import Foundation
import MWMeetings

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
    /// From one day with a cost.
    public let spend: Spending?
    /// From 20 delivered.
    public let dictation: Dictation?
    /// From three counted meetings.
    public let records: Records?
    /// The eight latest reached, oldest first; from one.
    public let milestones: [Milestone]?

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

    /// What a cost was spent on, in the order a month's bar stacks them from the bottom.
    public enum Purpose: String, Sendable, CaseIterable {
        case dictation, meeting, summary, naming
        /// Usage recorded before costs were split by purpose.
        case unsplit
    }

    /// Estimated US dollars.
    public struct Spending: Sendable, Equatable {
        /// The 12 months ending with this one, oldest first.
        public let months: [Month]
        /// Purposes with a cost in a shown month, in stacking order.
        public let series: [Purpose]
        /// Every day of this calendar year.
        public let thisYear: Double
        public let allTime: Double
        /// Σ every meeting row's costs ÷ Σ their hours; from one hour.
        public let perRecordedHour: Double?

        public var showsUnsplitCaption: Bool { series.contains(.unsplit) }
    }

    public struct Month: Sendable, Equatable {
        public let year: Int
        /// 1 to 12.
        public let month: Int
        /// The sum of its days by purpose; a purpose without a cost is left out.
        public let amounts: [Purpose: Double]
    }

    /// Delivered dictations: totals from the day rows, kept for life, and the typical and longest
    /// from the dictation rows, kept 13 months.
    public struct Dictation: Sendable, Equatable {
        public let words: Int
        /// Typing the timed words at `typingWPM`, less the time spent saying them; never below zero.
        public let savedTyping: TimeInterval
        public let typingWPM: Int
        /// Σ timed words ÷ Σ speaking minutes; nil without timed speech.
        public let wordsPerMinute: Double?
        /// Up to five, most delivered first; of equal counts, by bundle identifier.
        public let apps: [App]
        /// Median words; nil when no delivered row is left.
        public let typical: Double?
        public let longest: Int?
    }

    public struct App: Sendable, Equatable {
        public let bundleID: String
        public let count: Int
    }

    /// Over counted meetings; of equal records, the later wins.
    public struct Records: Sendable, Equatable {
        /// Its amount is seconds.
        public let longestMeeting: MeetingRecord?
        public let busiestDay: BusiestDay?
        public let mostWords: WordsDay?
        public let longestStreak: Streak?
        /// Its amount is speakers; nil while no meeting has one.
        public let mostSpeakers: MeetingRecord?
        /// Meetings, hours and dictations, a ladder with no step left out.
        public let next: [NextMilestone]
    }

    public struct MeetingRecord: Sendable, Equatable {
        public let id: UUID
        /// Local `yyyy-MM-dd` it started.
        public let day: String
        public let amount: Double
        /// Nil once the meeting is deleted.
        public let meeting: TimelineInputs.KeptMeeting?
    }

    /// The most counted meetings, then the most time recorded.
    public struct BusiestDay: Sendable, Equatable {
        public let day: String
        public let meetings: Int
        public let recorded: TimeInterval
    }

    /// Meeting words by start day plus words dictated.
    public struct WordsDay: Sendable, Equatable {
        public let day: String
        public let words: Int
    }
}

public enum TimelineStats {
    public static func compute(_ inputs: TimelineInputs) -> TimelineReport {
        let snapshot = inputs.snapshot
        let week = Week(firstWeekday: inputs.calendar.firstWeekday)
        let today = StatsTime.dayKey(inputs.now, calendar: inputs.calendar)
        let streaks = Streaks(snapshot)
        let meetings = MeetingPass(snapshot.meetings, week: week)
        let days = DayPass(snapshot.days, week: week)
        let milestones = Milestones(snapshot, streaks: streaks)

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

        let records = meetings.count >= 3 ? TimelineReport.Records(
            longestMeeting: meetings.longest.record(kept: inputs.kept),
            busiestDay: meetings.meetingsByDay.max { busier($1, than: $0, recorded: meetings.recordedByDay) }.map {
                TimelineReport.BusiestDay(day: $0.key, meetings: $0.value, recorded: meetings.recordedByDay[$0.key, default: 0])
            },
            mostWords: meetings.wordsByDay.merging(days.wordsByDay, uniquingKeysWith: +)
                .filter { $0.value > 0 }
                .max { ($0.value, $0.key) < ($1.value, $1.key) }
                .map { TimelineReport.WordsDay(day: $0.key, words: $0.value) },
            longestStreak: streaks.longest,
            mostSpeakers: meetings.mostSpeakers.record(kept: inputs.kept),
            next: [.meetings, .hours, .dictations].compactMap(milestones.next)
        ) : nil

        return TimelineReport(
            weekdays: week.weekdays, totals: totals,
            year: theYear(streaks, meetings: meetings, days: days, week: week, today: today),
            rhythm: rhythm, talkShare: talkShare,
            spend: days.costDays > 0 ? spending(meetings: meetings, days: days, today: today) : nil,
            dictation: days.delivered >= 20 ? dictation(days, snapshot.dictations, typingWPM: inputs.typingWPM) : nil,
            records: records,
            milestones: milestones.latest.isEmpty ? nil : milestones.latest
        )
    }

    // MARK: - The year

    private static func theYear(
        _ streaks: Streaks, meetings: MeetingPass, days: DayPass, week: Week, today: String
    ) -> TimelineReport.Year? {
        guard let first = streaks.activeDays.first.flatMap(year(of:)), let thisYear = year(of: today) else { return nil }
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

    // MARK: - Spend

    private static func spending(meetings: MeetingPass, days: DayPass, today: String) -> TimelineReport.Spending {
        let thisYear = year(of: today) ?? 0
        let thisMonth = thisYear * 12 + (Int(today.dropFirst(5).prefix(2)) ?? 1) - 1
        let months = (thisMonth - 11...thisMonth).map { index in
            let (year, month) = (index / 12, index % 12 + 1)
            return TimelineReport.Month(
                year: year, month: month,
                amounts: days.spendByMonth[String(format: "%04d-%02d", year, month), default: [:]]
            )
        }
        let hours = meetings.allRecorded / 3_600
        return TimelineReport.Spending(
            months: months,
            series: TimelineReport.Purpose.allCases.filter { purpose in months.contains { $0.amounts[purpose] != nil } },
            thisYear: days.spendByYear[thisYear, default: 0], allTime: days.spend,
            perRecordedHour: hours >= 1 ? meetings.allCosts / hours : nil
        )
    }

    // MARK: - Dictation

    private static func dictation(_ days: DayPass, _ rows: [DictationRow], typingWPM: Int) -> TimelineReport.Dictation {
        let words = rows.compactMap { $0.outcome == .delivered ? $0.words : nil }
        return TimelineReport.Dictation(
            words: days.words,
            savedTyping: TypingSpeed.saved(timedWords: days.timedWords, spoken: days.seconds, wpm: typingWPM),
            typingWPM: typingWPM,
            wordsPerMinute: days.seconds > 0 ? Double(days.timedWords) / (days.seconds / 60) : nil,
            apps: days.apps.filter { $0.key != "other" }
                .sorted { ($1.value, $0.key) < ($0.value, $1.key) }
                .prefix(5)
                .map { TimelineReport.App(bundleID: $0.key, count: $0.value) },
            typical: DelayStats(samples: words.map(Double.init))?.median,
            longest: words.max()
        )
    }

    // MARK: - Records

    /// More counted meetings, then more time recorded, then the later day.
    private static func busier(
        _ day: (key: String, value: Int), than other: (key: String, value: Int), recorded: [String: TimeInterval]
    ) -> Bool {
        (day.value, recorded[day.key, default: 0], day.key) > (other.value, recorded[other.key, default: 0], other.key)
    }

    /// The meeting with the greatest amount; of equal amounts, the later start.
    private struct Leader {
        private var best: (id: UUID, day: String, amount: Double, start: Date)?

        mutating func offer(_ id: UUID, day: String, amount: Double, start: Date) {
            guard amount > 0 else { return }
            if let best, (amount, start) < (best.amount, best.start) { return }
            best = (id, day, amount, start)
        }

        func record(kept: [UUID: TimelineInputs.KeptMeeting]) -> TimelineReport.MeetingRecord? {
            best.map { TimelineReport.MeetingRecord(id: $0.id, day: $0.day, amount: $0.amount, meeting: kept[$0.id]) }
        }
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

    /// One pass over the meetings; all but spend count counted meetings only.
    private struct MeetingPass {
        var count = 0
        var recorded: TimeInterval = 0
        var words = 0
        /// Every row's, a meeting under a minute included.
        var allRecorded: TimeInterval = 0
        var allCosts: Double = 0
        var recordedByDay: [String: TimeInterval] = [:]
        var meetingsByDay: [String: Int] = [:]
        var wordsByDay: [String: Int] = [:]
        var longest = Leader()
        var mostSpeakers = Leader()
        var rhythm = Week.emptyGrid
        var earliestStart: TimeInterval?
        var latestFinish: TimeInterval?
        var backToBack = 0
        var talk = Talk()
        private var spans: [(start: Date, end: Date)] = []

        init(_ rows: [MeetingRow], week: Week) {
            for row in rows {
                allRecorded += row.duration
                allCosts += row.usd.meeting + row.usd.summary + row.usd.naming
                guard row.isCounted else { continue }
                count += 1
                recorded += row.duration
                words += row.words
                let start = row.localStart
                if let day = row.startDay {
                    recordedByDay[day, default: 0] += row.duration
                    meetingsByDay[day, default: 0] += 1
                    wordsByDay[day, default: 0] += row.words
                    if let date = start?.date {
                        longest.offer(row.id, day: day, amount: row.duration, start: date)
                        mostSpeakers.offer(row.id, day: day, amount: Double(row.speakers.count), start: date)
                    }
                }
                if let start { add(start: start, end: row.localEnd, week: week) }
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
        var words = 0
        var seconds: TimeInterval = 0
        var timedWords = 0
        var apps: [String: Int] = [:]
        var wordsByDay: [String: Int] = [:]
        var spend: Double = 0
        var costDays = 0
        var spendByYear: [Int: Double] = [:]
        /// By `yyyy-MM`.
        var spendByMonth: [String: [TimelineReport.Purpose: Double]] = [:]
        var deliveredByDay: [String: Int] = [:]
        var dictationDays: [Int: Int] = [:]
        var rhythm = Week.emptyGrid

        init(_ rows: [DayRow], week: Week) {
            for row in rows {
                add(spendOf: row)
                words += row.words
                seconds += row.seconds
                timedWords += row.timedWords
                apps.merge(row.apps, uniquingKeysWith: +)
                if row.words > 0 { wordsByDay[row.day, default: 0] += row.words }
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

        /// In key order, so equal records always sum to the same total.
        private mutating func add(spendOf row: DayRow) {
            var cost: Double = 0
            for (key, amount) in row.spend.sorted(by: { $0.key < $1.key }) {
                cost += amount.usd
                if amount.usd != 0, let purpose = TimelineReport.Purpose(rawValue: key) {
                    spendByMonth[String(row.day.prefix(7)), default: [:]][purpose, default: 0] += amount.usd
                }
            }
            spend += cost
            guard cost > 0 else { return }
            costDays += 1
            if let year = year(of: row.day) { spendByYear[year, default: 0] += cost }
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
