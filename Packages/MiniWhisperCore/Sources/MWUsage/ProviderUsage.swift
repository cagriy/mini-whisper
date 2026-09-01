/// One dictation's provider-attributed usage, as the pipeline hands it to the store.
public struct ProviderUsage: Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var streamedSeconds: [String: Double]
    public var costUSD: Double

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        streamedSeconds: [String: Double] = [:],
        costUSD: Double = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.streamedSeconds = streamedSeconds
        self.costUSD = costUSD
    }
}
