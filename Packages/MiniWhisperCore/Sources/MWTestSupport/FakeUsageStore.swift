import Foundation
import MWConfig
import MWUsage

/// In-memory `UsageRecording`: accumulates like the real store but touches no config
/// file, and records what the pipeline billed.
public final class FakeUsageStore: UsageRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ProviderUsage] = []
    private var entry: DayEntry
    private var month: Double

    public init(today: DayEntry = DayEntry(), monthCost: Double = 0) {
        entry = today
        month = monthCost
    }

    public var added: [ProviderUsage] { lock.withLock { recorded } }

    @discardableResult
    public func add(_ usage: ProviderUsage) async throws -> DayEntry {
        lock.withLock {
            recorded.append(usage)
            entry.inputTokens += usage.inputTokens
            entry.outputTokens += usage.outputTokens
            entry.costUSD += usage.costUSD
            for (engine, seconds) in usage.streamedSeconds {
                entry.streamedSeconds[engine, default: 0] += seconds
            }
            month += usage.costUSD
            return entry
        }
    }

    public func totals() async -> (today: DayEntry, monthCost: Double) {
        lock.withLock { (entry, month) }
    }
}
