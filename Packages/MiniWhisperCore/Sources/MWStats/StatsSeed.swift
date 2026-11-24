import Foundation
import MWConfig
import MWHistory
import MWMeetings
import MWUsage

/// The record as the stored files can rebuild it: a row per history entry, this month's usage as
/// one unsplit cost a day, and earlier months' costs from the meetings still stored. Each cost
/// lands once: this month's usage already holds this month's dictations and meetings. Numbers and
/// identifiers only.
public struct StatsSeed: Sendable, Equatable {
    /// One `delivered` row per history entry, oldest first.
    public let dictations: [DictationRow]
    /// One a day, oldest first.
    public let days: [DayRow]
    /// Earlier months' meetings that added a cost.
    public let meetingsWithCost: Int

    /// `meetings` is every stored meeting: finished non-test meetings give earlier months' costs,
    /// finished test calls come out of this month's usage, and the rest are passed over.
    public init(
        history: [HistoryEntry], usage: [String: DayUsage], meetings: [Meeting], now: Date, calendar: Calendar
    ) {
        func day(_ date: Date) -> String { StatsTime.dayKey(date, calendar: calendar) }
        let month = day(now).prefix(7)
        let monthStart = "\(month)-01"
        var lines: [String: DayRow] = [:]
        func add(_ line: DayRow) { lines[line.day, default: DayRow(day: line.day)].add(line) }

        // Sorted throughout, so the floating-point sums do not depend on input order.
        var dictations: [DictationRow] = []
        for entry in history.sorted(by: { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }) {
            let words = WordCount.count(entry.text)
            dictations.append(DictationRow(
                id: entry.id, at: StatsTime.iso(entry.timestamp, timeZone: calendar.timeZone), app: entry.bundleID,
                engine: entry.engine, seconds: entry.streamedSeconds, words: words, outcome: .delivered,
                usd: entry.costUSD, seeded: true
            ))
            var line = DayRow(
                day: day(entry.timestamp), delivered: 1, words: words, apps: [entry.bundleID ?? "other": 1],
                hours: [String(StatsTime.hour(entry.timestamp, calendar: calendar)): 1]
            )
            if entry.streamedSeconds > 0 {
                line.seconds = entry.streamedSeconds
                line.timedWords = words
            }
            if line.day < monthStart {
                var spend = Spend(usd: entry.costUSD)
                if let engine = entry.engine, entry.streamedSeconds > 0 {
                    spend.seconds = [engine: entry.streamedSeconds]
                }
                line.spend = Self.nonEmpty([UsagePurpose.dictation.rawValue: spend])
            }
            add(line)
        }

        let stored = meetings.sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }

        // A test call's usage reached `config.usage` the day it ended but is no part of the record.
        var testCalls: [String: Spend] = [:]
        for meeting in stored where meeting.test != nil {
            guard let end = meeting.endedAt else { continue }
            testCalls[day(end), default: Spend()].add(Spend(
                usd: meeting.totalCostUSD, seconds: [meeting.engine.pricingKey: meeting.billing.engineSeconds]
            ))
        }
        for (key, usage) in usage.sorted(by: { $0.key < $1.key }) where key.prefix(7) == month {
            let test = testCalls[key] ?? Spend()
            let seconds = usage.streamedSeconds.merging(test.seconds.mapValues { -$0 }, uniquingKeysWith: +)
            let spend = Self.nonEmpty(["unsplit": Spend(
                usd: max(0, usage.costUSD - test.usd), tokensIn: usage.inputTokens, tokensOut: usage.outputTokens,
                seconds: seconds.filter { $0.value > 0 }
            )])
            if !spend.isEmpty { add(DayRow(day: key, spend: spend)) }
        }

        var meetingsWithCost = 0
        for meeting in stored where meeting.test == nil && meeting.endedAt != nil {
            let start = day(meeting.startedAt)
            guard start < monthStart else { continue }
            let billing = meeting.billing
            let spend = Self.nonEmpty([
                UsagePurpose.meeting.rawValue: Spend(
                    usd: billing.costUSD,
                    seconds: billing.engineSeconds > 0 ? [meeting.engine.pricingKey: billing.engineSeconds] : [:]
                ),
                UsagePurpose.summary.rawValue: Spend(
                    usd: (meeting.summary?.costUSD ?? 0) + billing.replacedSummaryCostUSD,
                    tokensIn: meeting.summary?.inputTokens ?? 0, tokensOut: meeting.summary?.outputTokens ?? 0
                ),
                UsagePurpose.naming.rawValue: Spend(usd: billing.namingCostUSD),
            ])
            guard !spend.isEmpty else { continue }
            meetingsWithCost += 1
            add(DayRow(day: start, spend: spend))
        }

        self.dictations = dictations
        days = lines.values.sorted { $0.day < $1.day }
        self.meetingsWithCost = meetingsWithCost
    }

    private static func nonEmpty(_ spend: [String: Spend]) -> [String: Spend] {
        spend.filter { $0.value != Spend() }
    }
}
