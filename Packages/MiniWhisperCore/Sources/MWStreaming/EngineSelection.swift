import MWConfig

/// The one-per-run line the overlay shows when selection had to downgrade (F23).
public enum EngineNotice: Sendable, Hashable {
    case speechPermissionPointer
    case cloudKeyMissing(EngineName)

    public var message: String {
        switch self {
        case .speechPermissionPointer:
            "Live transcript off: enable Speech Recognition in System Settings → Privacy & Security."
        case .cloudKeyMissing(let engine):
            "Live transcript: \(Self.label(engine)) key missing — using on-device"
        }
    }

    /// Only the cloud engines can be missing a key, so only they need a display name.
    private static func label(_ engine: EngineName) -> String {
        switch engine {
        case .openai: "OpenAI"
        case .elevenlabs: "ElevenLabs"
        case .speechmatics: "Speechmatics"
        case .onDevice, .speechAnalyzer: engine.rawValue
        }
    }
}

/// What one press gets: the engine to stream through, if any, plus a notice to show.
public struct EngineSelection: Sendable {
    public var engine: (any StreamingEngine)?
    public var notice: EngineNotice?

    public init(engine: (any StreamingEngine)? = nil, notice: EngineNotice? = nil) {
        self.engine = engine
        self.notice = notice
    }
}
