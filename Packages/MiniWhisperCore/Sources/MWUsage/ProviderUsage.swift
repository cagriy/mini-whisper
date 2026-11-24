/// What a usage paid for. The statistics record splits spend by it; `config.usage` ignores it.
public enum UsagePurpose: String, Sendable, Codable {
    case dictation, meeting, summary, naming
    /// Kept out of the statistics; still billed in `config.usage`.
    case testCall = "test_call"
}

/// One provider-attributed usage, as a producer hands it to the store.
public struct ProviderUsage: Sendable, Equatable {
    public var purpose: UsagePurpose
    public var inputTokens: Int
    public var outputTokens: Int
    public var streamedSeconds: [String: Double]
    public var costUSD: Double

    /// `purpose` has no default, so every producer states it.
    public init(
        purpose: UsagePurpose,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        streamedSeconds: [String: Double] = [:],
        costUSD: Double = 0
    ) {
        self.purpose = purpose
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.streamedSeconds = streamedSeconds
        self.costUSD = costUSD
    }
}
