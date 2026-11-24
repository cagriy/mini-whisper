import MWUsage

/// A `UsageRecording` that also records each usage's spend in the statistics record, before the
/// usage store can fail, so spend is kept even when `config.json` cannot be written.
public struct RecordedUsage: UsageRecording {
    private let base: any UsageRecording
    private let stats: StatsStore

    public init(base: any UsageRecording, stats: StatsStore) {
        self.base = base
        self.stats = stats
    }

    @discardableResult
    public func add(_ usage: ProviderUsage) async throws -> DayEntry {
        if usage.purpose != .testCall { await stats.record(spend: usage) }
        return try await base.add(usage)
    }

    public func totals() async -> UsageTotals {
        await base.totals()
    }
}
