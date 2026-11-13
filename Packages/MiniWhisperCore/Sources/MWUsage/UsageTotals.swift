import MWConfig

/// Usage for the menu's two rows and the sidebar table: today, and the current month with
/// today in it.
public struct UsageTotals: Equatable, Sendable {
    public var today: DayEntry
    public var month: DayEntry

    public init(today: DayEntry = DayEntry(), month: DayEntry = DayEntry()) {
        self.today = today
        self.month = month
    }
}

/// The usage table's cells, as `Pricing.usageTable` formats them.
public struct UsageTable: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        /// `in/out`.
        public var tokens: String
        public var audio: String
        public var cost: String

        public init(tokens: String, audio: String, cost: String) {
            self.tokens = tokens
            self.audio = audio
            self.cost = cost
        }
    }

    public var today: Row
    public var month: Row

    public init(today: Row, month: Row) {
        self.today = today
        self.month = month
    }
}

extension DayEntry {
    /// Tokens and cost added, streamed seconds merged per engine.
    public mutating func add(_ other: DayEntry) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        costUSD += other.costUSD
        for (engine, seconds) in other.streamedSeconds {
            streamedSeconds[engine, default: 0] += seconds
        }
    }

    public mutating func add(_ usage: ProviderUsage) {
        add(DayEntry(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            streamedSeconds: usage.streamedSeconds,
            costUSD: usage.costUSD
        ))
    }
}
