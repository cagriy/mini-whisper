/// How a meeting recognises voices: the bundled model on this Mac, or Speechmatics'
/// own speaker identifiers.
public enum VoiceRoute: String, Codable, CaseIterable, Sendable {
    case local
    case speechmatics
}

extension MeetingEngine {
    public var voiceRoute: VoiceRoute {
        switch self {
        case .speechmaticsStandard, .speechmaticsEnhanced: .speechmatics
        case .assemblyaiStreaming, .assemblyaiPro: .local
        }
    }
}

/// The `voice_*` keys of `config.json`: one switch per route and the tuning values.
public struct VoiceSettings: Equatable, Sendable {
    public enum Field: CaseIterable, Sendable {
        case sure, suggestion, margin, minimumSpeech, buffer, sensitivity
    }

    /// The slider, from 0 (Cautious) to 10 (Eager).
    public static let steps = 0...10

    public var localEnabled = false
    public var speechmaticsEnabled = false
    public var sureThreshold = 0.70
    public var suggestionThreshold = 0.50
    public var margin = 0.10
    public var minimumSpeechSeconds = 15.0
    public var bufferSeconds = 120.0
    public var speechmaticsSensitivity = 0.80

    public init() {}

    public func isEnabled(_ route: VoiceRoute) -> Bool {
        switch route {
        case .local: localEnabled
        case .speechmatics: speechmaticsEnabled
        }
    }

    /// The suggestion threshold is further held at or below the sure threshold.
    public static func range(of field: Field) -> ClosedRange<Double> {
        switch field {
        case .sure: 0.50...0.95
        case .suggestion: 0.30...0.90
        case .margin: 0...0.30
        case .minimumSpeech: 5...60
        case .buffer: 60...300
        case .sensitivity: 0...1
        }
    }

    public func value(of field: Field) -> Double {
        self[keyPath: Self.keyPath(of: field)]
    }

    public func setting(_ field: Field, to value: Double) -> VoiceSettings {
        var settings = self
        settings[keyPath: Self.keyPath(of: field)] = value
        return settings.validated()
    }

    /// The five slider values of `step`; the switches and the buffer are kept.
    public func tuned(toStep step: Int) -> VoiceSettings {
        let step = step.clamped(to: Self.steps)
        var tuned = self
        for field in Field.allCases {
            if let value = Self.value(of: field, atStep: step) {
                tuned[keyPath: Self.keyPath(of: field)] = value
            }
        }
        return tuned
    }

    /// The step whose five values all match the stored ones, or nil for a hand-set value.
    public var step: Int? {
        Self.steps.first { step in
            Field.allCases.allSatisfy { field in
                guard let target = Self.value(of: field, atStep: step) else { return true }
                let tolerance = field == .minimumSpeech ? 0.5 : 0.005
                return abs(value(of: field) - target) <= tolerance
            }
        }
    }

    public func validated() -> VoiceSettings {
        var validated = self
        for field in Field.allCases {
            validated[keyPath: Self.keyPath(of: field)] = value(of: field).clamped(to: Self.range(of: field))
        }
        validated.suggestionThreshold = min(validated.suggestionThreshold, validated.sureThreshold)
        return validated
    }

    static func keyPath(of field: Field) -> WritableKeyPath<VoiceSettings, Double> {
        switch field {
        case .sure: \.sureThreshold
        case .suggestion: \.suggestionThreshold
        case .margin: \.margin
        case .minimumSpeech: \.minimumSpeechSeconds
        case .buffer: \.bufferSeconds
        case .sensitivity: \.speechmaticsSensitivity
        }
    }

    /// Worked in hundredths so each step lands on the exact decimal (0.70, not
    /// 0.7000000000000001) and step 5 equals the defaults.
    private static func value(of field: Field, atStep step: Int) -> Double? {
        let hundredths: Int? =
            switch field {
            case .sure: 80 - 2 * step
            case .suggestion: 60 - 2 * step
            case .margin: 15 - step
            case .minimumSpeech: 2500 - 200 * step
            case .sensitivity: 95 - 3 * step
            case .buffer: nil
            }
        return hundredths.map { Double($0) / 100 }
    }
}
