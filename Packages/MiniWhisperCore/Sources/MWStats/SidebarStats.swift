import Foundation

/// The sidebar block: six figures over the last 30 days, their trend and one lifetime line.
/// Durations are in seconds. Meetings under a minute are left out of every figure.
public struct SidebarStats: Sendable, Equatable {
    /// Today and the 29 local days before it.
    public static let days = 30

    public let meetings: Int
    public let recorded: TimeInterval
    public let dictations: Int
    /// Typing the timed dictated words at the typing speed, less the time spent saying them;
    /// never below zero.
    public let savedTyping: TimeInterval
    public let wordsTranscribed: Int
    public let wordsDictated: Int
    /// Time recorded on each day of the window, oldest first, so today is last.
    public let trend: [TimeInterval]
    public let lifetimeMeetings: Int
    public let lifetimeRecorded: TimeInterval

    /// Nil until the record holds a counted meeting or a delivered dictation. A meeting falls on
    /// the local day it started where it took place; a day row on its own `day`.
    public init?(snapshot: StatsSnapshot, typingWPM: Int, now: Date, calendar: Calendar) {
        let window = Self.window(now: now, calendar: calendar)

        var meetings = 0, wordsTranscribed = 0, lifetimeMeetings = 0
        var recorded: TimeInterval = 0, lifetimeRecorded: TimeInterval = 0
        var trend = [TimeInterval](repeating: 0, count: Self.days)
        for row in snapshot.meetings where row.isCounted {
            lifetimeMeetings += 1
            lifetimeRecorded += row.duration
            guard let day = row.startDay, let index = window[day] else { continue }
            meetings += 1
            recorded += row.duration
            wordsTranscribed += row.words
            trend[index] += row.duration
        }

        var everDelivered = false
        var dictations = 0, wordsDictated = 0, timedWords = 0
        var spoken: TimeInterval = 0
        for day in snapshot.days {
            everDelivered = everDelivered || day.delivered > 0
            guard window[day.day] != nil else { continue }
            dictations += day.delivered
            wordsDictated += day.words
            timedWords += day.timedWords
            spoken += day.seconds
        }

        guard lifetimeMeetings > 0 || everDelivered else { return nil }
        self.meetings = meetings
        self.recorded = recorded
        self.dictations = dictations
        self.savedTyping = typingWPM > 0 ? max(0, Double(timedWords) / Double(typingWPM) * 60 - spoken) : 0
        self.wordsTranscribed = wordsTranscribed
        self.wordsDictated = wordsDictated
        self.trend = trend
        self.lifetimeMeetings = lifetimeMeetings
        self.lifetimeRecorded = lifetimeRecorded
    }

    /// Each day key of the window and its place in the trend. Days are counted on the calendar
    /// from midday, so a change of clock never shifts the window by a day.
    private static func window(now: Date, calendar: Calendar) -> [String: Int] {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let midday = gregorian.startOfDay(for: now).addingTimeInterval(12 * 3_600)
        var window: [String: Int] = [:]
        for index in 0..<days {
            let date = gregorian.date(byAdding: .day, value: index - (days - 1), to: midday) ?? midday
            window[StatsTime.dayKey(date, calendar: calendar)] = index
        }
        return window
    }
}
