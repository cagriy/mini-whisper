/// The four diarizing providers a meeting can stream to (`meeting_engine`, design §5.2).
public enum MeetingEngine: String, Codable, CaseIterable, Sendable {
    case speechmaticsStandard = "speechmatics_standard"
    case speechmaticsEnhanced = "speechmatics_enhanced"
    case assemblyaiStreaming = "assemblyai_streaming"
    case assemblyaiPro = "assemblyai_pro"

    public var keyAccount: KeyAccount {
        switch self {
        case .speechmaticsStandard, .speechmaticsEnhanced: .speechmatics
        case .assemblyaiStreaming, .assemblyaiPro: .assemblyai
        }
    }

    /// `Pricing.perMinute` key the meeting's seconds bill under.
    public var pricingKey: String {
        switch self {
        case .speechmaticsStandard: "speechmatics"
        case .speechmaticsEnhanced: "speechmatics_enhanced"
        case .assemblyaiStreaming: "assemblyai"
        case .assemblyaiPro: "assemblyai_pro"
        }
    }

    /// AssemblyAI bills speaker labels as a separate per-minute add-on.
    public var diarizationPricingKey: String? {
        switch self {
        case .speechmaticsStandard, .speechmaticsEnhanced: nil
        case .assemblyaiStreaming, .assemblyaiPro: "assemblyai_diarization"
        }
    }

    public var title: String {
        switch self {
        case .speechmaticsStandard: "Speechmatics Standard"
        case .speechmaticsEnhanced: "Speechmatics Enhanced"
        case .assemblyaiStreaming: "AssemblyAI Universal-Streaming"
        case .assemblyaiPro: "AssemblyAI Universal 3.6 Pro"
        }
    }

    public var providerModel: String {
        switch self {
        case .speechmaticsStandard: "standard"
        case .speechmaticsEnhanced: "enhanced"
        case .assemblyaiStreaming: "universal-streaming-english"
        case .assemblyaiPro: "universal-3-6-pro"
        }
    }

    /// The stored tier when its key exists, else the first tier with a key (R4).
    public static func resolve(stored: MeetingEngine?, hasKey: (KeyAccount) -> Bool) -> MeetingEngine? {
        if let stored, hasKey(stored.keyAccount) { return stored }
        return allCases.first { hasKey($0.keyAccount) }
    }
}
