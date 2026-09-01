import Foundation
import MWConfig

/// The pipeline's seam over usage accounting.
public protocol UsageRecording: Sendable {
    @discardableResult
    func add(_ usage: ProviderUsage) async throws -> DayEntry
    func totals() async -> (today: DayEntry, monthCost: Double)
}

/// Accumulates one dictation's usage into today's entry in `config.json`, pruning days
/// outside the current calendar month on every write (F35). A port of
/// `config.py:add_usage` / `usage_totals`; the actor gives the Python lock's serialisation.
public actor UsageStore: UsageRecording {
    private let config: ConfigStore
    private let today: @Sendable () -> Date

    public init(config: ConfigStore, today: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.today = today
    }

    @discardableResult
    public func add(_ usage: ProviderUsage) async throws -> DayEntry {
        let day = Self.dayKey(today())
        let month = Self.monthKey(day)
        try await config.update { config in
            var entry = config.usage[day] ?? DayEntry()
            entry.inputTokens += usage.inputTokens
            entry.outputTokens += usage.outputTokens
            entry.costUSD += usage.costUSD
            for (engine, seconds) in usage.streamedSeconds {
                entry.streamedSeconds[engine, default: 0] += seconds
            }
            config.usage = config.usage.filter { Self.monthKey($0.key) == month }
            config.usage[day] = entry
        }
        return await config.load().usage[day] ?? DayEntry()
    }

    public func totals() async -> (today: DayEntry, monthCost: Double) {
        let day = Self.dayKey(today())
        let month = Self.monthKey(day)
        let usage = await config.load().usage
        let monthCost = usage
            .filter { Self.monthKey($0.key) == month }
            .values
            .reduce(0) { $0 + $1.costUSD }
        return (usage[day] ?? DayEntry(), monthCost)
    }

    private nonisolated static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func monthKey(_ day: String) -> String {
        String(day.prefix(7))
    }
}
