import Foundation
import MWConfig
import MWUsage

/// In-memory `UsageRecording`: accumulates like the real store but touches no config
/// file, and records what the pipeline billed.
public final class FakeUsageStore: UsageRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ProviderUsage] = []
    private var entry: DayEntry
    private var month: DayEntry

    public init(today: DayEntry = DayEntry(), month: DayEntry = DayEntry()) {
        entry = today
        self.month = month
    }

    public var added: [ProviderUsage] { lock.withLock { recorded } }

    @discardableResult
    public func add(_ usage: ProviderUsage) async throws -> DayEntry {
        lock.withLock {
            recorded.append(usage)
            entry.add(usage)
            month.add(usage)
            return entry
        }
    }

    public func totals() async -> UsageTotals {
        lock.withLock { UsageTotals(today: entry, month: month) }
    }
}
