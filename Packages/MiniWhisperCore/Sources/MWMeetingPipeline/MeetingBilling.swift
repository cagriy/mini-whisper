import MWConfig
import MWMeetings
import MWSupport
import MWUsage

/// A meeting's cost: the live estimate while recording, and the usage records for Stop and for
/// its summary (design §3 R18, §5.3).
public struct MeetingBilling: Sendable {
    private let engine: MeetingEngine
    private let overrides: [String: Double]
    /// Audio seconds fed to the provider.
    public private(set) var engineSeconds: Double = 0

    public init(engine: MeetingEngine, overrides: [String: Double]) {
        self.engine = engine
        self.overrides = overrides
    }

    public mutating func add(seconds: Double) {
        engineSeconds += seconds
    }

    /// The engine's rate plus, for AssemblyAI, the diarization add-on.
    public var liveCost: Double {
        Pricing.meetingCost(engine: engine, seconds: engineSeconds, tokens: TokenUsage(), overrides: overrides)
    }

    /// `meeting.json`'s `billing`.
    public var totals: Billing {
        Billing(
            engineSeconds: engineSeconds,
            diarizationSeconds: engine.diarizationPricingKey == nil ? 0 : engineSeconds,
            costUSD: liveCost
        )
    }

    /// The seconds go under the engine's pricing key only, with the add-on inside the cost: a
    /// second key would count the same minutes twice in the Today row.
    public func finalUsage() -> ProviderUsage {
        ProviderUsage(streamedSeconds: [engine.pricingKey: engineSeconds], costUSD: liveCost)
    }

    public func summaryUsage(_ tokens: TokenUsage) -> ProviderUsage {
        ProviderUsage(
            inputTokens: tokens.inputTokens,
            outputTokens: tokens.outputTokens,
            costUSD: Pricing.meetingCost(engine: engine, seconds: 0, tokens: tokens, overrides: overrides)
        )
    }
}
