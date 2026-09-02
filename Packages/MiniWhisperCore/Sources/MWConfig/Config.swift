import Foundation

/// Loss-tolerant JSON value used to round-trip keys this version does not know about (F2).
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
    init(_ stringValue: String) { self.stringValue = stringValue }
}

/// One day's provider-attributed usage, as `config.py:_new_day_entry` writes it.
public struct DayUsage: Equatable, Sendable {
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

extension DayUsage: Codable {
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case streamedSeconds = "streamed_seconds"
        case costUSD = "cost_usd"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        streamedSeconds = try container.decodeIfPresent([String: Double].self, forKey: .streamedSeconds) ?? [:]
        costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
    }
}

/// `config.json` as a value: the seven Python keys, the F4 additions, and every unknown
/// key preserved verbatim so the Python app keeps working alongside this one (N6).
public struct Config: Equatable, Sendable {
    public var hotkey = "shift+cmd_r"
    public var submitHotkey = "cmd_r"
    public var cleanupEnabled = true
    public var soundVolume = 1.0
    public var streamingEnabled = true
    /// Absent from `config.json` means "no explicit choice" — the platform default
    /// applies (F32). First run leaves it absent, so a new install follows the model
    /// rather than pinning `on_device` before the model is even downloaded.
    public var streamingEngine: EngineName?
    /// Raw `streaming_engine` value that this build does not recognise, kept only so
    /// that saving round-trips it (F2). Never honoured at runtime.
    var unrecognisedStreamingEngine: String?
    public var pricingOverrides: [String: Double] = [:]
    public var usage: [String: DayUsage] = [:]
    public var historyRetentionDays = 7
    public var idleStopSeconds = 60
    public var toggleMaxSeconds = 300
    public var speechModelPrompted = false
    public var vocabulary: [String] = []
    public var profiles: [Profile] = []
    public var extra: [String: JSONValue] = [:]

    public init() {}

    /// Applies the bounds and uniqueness rules of design §5.3.
    public func validated() -> Config {
        var validated = self
        validated.historyRetentionDays = historyRetentionDays.clamped(to: 0...30)
        validated.idleStopSeconds = idleStopSeconds.clamped(to: 10...600)
        validated.toggleMaxSeconds = toggleMaxSeconds.clamped(to: 60...1800)
        var claimed: Set<String> = []
        validated.profiles = profiles.map { profile in
            var profile = profile
            profile.bundleIDs = profile.bundleIDs.filter { claimed.insert($0).inserted }
            return profile
        }
        return validated
    }

    /// Pretty-printed with a two-space indent and a trailing newline, matching
    /// `config.py:save`'s `json.dumps(indent=2) + "\n"`.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}

extension Config: Codable {
    private enum Key {
        static let hotkey = "hotkey"
        static let submitHotkey = "submit_hotkey"
        static let cleanupEnabled = "cleanup_enabled"
        static let soundVolume = "sound_volume"
        static let streamingEnabled = "streaming_enabled"
        static let streamingEngine = "streaming_engine"
        static let pricingOverrides = "pricing_overrides"
        static let usage = "usage"
        static let historyRetentionDays = "history_retention_days"
        static let idleStopSeconds = "idle_stop_seconds"
        static let toggleMaxSeconds = "toggle_max_seconds"
        static let speechModelPrompted = "speech_model_prompted"
        static let vocabulary = "vocabulary"
        static let profiles = "profiles"

        static let all: Set<String> = [
            hotkey, submitHotkey, cleanupEnabled, soundVolume, streamingEnabled, streamingEngine,
            pricingOverrides, usage, historyRetentionDays, idleStopSeconds, toggleMaxSeconds,
            speechModelPrompted, vocabulary, profiles,
        ]
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        func value<T: Decodable>(_ key: String) throws -> T? {
            try container.decodeIfPresent(T.self, forKey: AnyCodingKey(key))
        }

        if let value: String = try value(Key.hotkey) { hotkey = value }
        if let value: String = try value(Key.submitHotkey) { submitHotkey = value }
        if let value: Bool = try value(Key.cleanupEnabled) { cleanupEnabled = value }
        if let value: Double = try value(Key.soundVolume) { soundVolume = value }
        if let value: Bool = try value(Key.streamingEnabled) { streamingEnabled = value }
        if let value: [String: Double] = try value(Key.pricingOverrides) { pricingOverrides = value }
        if let value: [String: DayUsage] = try value(Key.usage) { usage = value }
        if let value: Int = try value(Key.historyRetentionDays) { historyRetentionDays = value }
        if let value: Int = try value(Key.idleStopSeconds) { idleStopSeconds = value }
        if let value: Int = try value(Key.toggleMaxSeconds) { toggleMaxSeconds = value }
        if let value: Bool = try value(Key.speechModelPrompted) { speechModelPrompted = value }
        if let value: [String] = try value(Key.vocabulary) { vocabulary = value }
        if let value: [Profile] = try value(Key.profiles) { profiles = value }

        let engine: String? = try value(Key.streamingEngine)
        streamingEngine = engine.flatMap(EngineName.init(rawValue:))
        // A value this build does not know — written by a newer one, or by hand. It is
        // ignored at runtime (F32 picks the platform default) but kept so saving here
        // does not destroy it (F2).
        unrecognisedStreamingEngine = streamingEngine == nil ? engine : nil

        for key in container.allKeys where !Key.all.contains(key.stringValue) {
            extra[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(hotkey, forKey: AnyCodingKey(Key.hotkey))
        try container.encode(submitHotkey, forKey: AnyCodingKey(Key.submitHotkey))
        try container.encode(cleanupEnabled, forKey: AnyCodingKey(Key.cleanupEnabled))
        try container.encode(soundVolume, forKey: AnyCodingKey(Key.soundVolume))
        try container.encode(streamingEnabled, forKey: AnyCodingKey(Key.streamingEnabled))
        if let streamingEngine {
            try container.encode(streamingEngine, forKey: AnyCodingKey(Key.streamingEngine))
        } else if let unrecognisedStreamingEngine {
            try container.encode(unrecognisedStreamingEngine, forKey: AnyCodingKey(Key.streamingEngine))
        }
        try container.encode(pricingOverrides, forKey: AnyCodingKey(Key.pricingOverrides))
        try container.encode(usage, forKey: AnyCodingKey(Key.usage))
        try container.encode(historyRetentionDays, forKey: AnyCodingKey(Key.historyRetentionDays))
        try container.encode(idleStopSeconds, forKey: AnyCodingKey(Key.idleStopSeconds))
        try container.encode(toggleMaxSeconds, forKey: AnyCodingKey(Key.toggleMaxSeconds))
        try container.encode(speechModelPrompted, forKey: AnyCodingKey(Key.speechModelPrompted))
        try container.encode(vocabulary, forKey: AnyCodingKey(Key.vocabulary))
        try container.encode(profiles, forKey: AnyCodingKey(Key.profiles))

        for (key, value) in extra where !Key.all.contains(key) {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension JSONValue {
    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}
