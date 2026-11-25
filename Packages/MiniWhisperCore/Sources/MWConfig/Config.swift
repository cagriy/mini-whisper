import Foundation
import MWOverlaySim

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
    /// Which animation the recording card draws (design §5.2). Unlike `streamingEngine`
    /// this is non-optional: an absent key means the default, which is written back.
    public var overlayStyle: OverlayStyle = .default {
        didSet { unrecognisedOverlayStyle = nil }
    }
    /// Raw `overlay_style` value that this build does not recognise, kept only so that
    /// saving round-trips it (F2). Never honoured at runtime.
    var unrecognisedOverlayStyle: String?
    /// Like `overlayStyle`: an absent key means the default, which is written back.
    public var theme: AppTheme = .system {
        didSet { unrecognisedTheme = nil }
    }
    /// Raw `theme` value that this build does not recognise, kept only so that saving
    /// round-trips it. Never honoured at runtime.
    var unrecognisedTheme: String?
    /// Like `theme`: an absent key means the default, which is written back.
    public var updateChannel: UpdateChannel = .release {
        didSet { unrecognisedUpdateChannel = nil }
    }
    /// Raw `update_channel` value that this build does not recognise, kept only so that
    /// saving round-trips it. Never honoured at runtime.
    var unrecognisedUpdateChannel: String?
    /// Absent until the main window's frame is first saved.
    public var mainWindowFrame: WindowFrame?
    public var meetingHotkey = "ctrl+alt+cmd+m"
    /// Absent means "first tier with a key" (`MeetingEngine.resolve`).
    public var meetingEngine: MeetingEngine?
    /// Raw `meeting_engine` value this build does not recognise, kept only so that
    /// saving round-trips it (F2). Never honoured at runtime.
    var unrecognisedMeetingEngine: String?
    public var meetingKeepAudio = true
    /// Absent means the macOS account's full name, resolved at use.
    public var meetingUserName: String?
    public var meetingSystemAudioExplained = false
    public var meetingNamingEnabled = true
    public var meetingNamingAutoApply = false
    /// Spellings of the user's name as transcription mishears it.
    public var meetingUserNameAliases: [String] = []
    public var meetingNamingExplained = false
    /// Seconds without speech before a recording meeting asks whether to stop; 0 is Off.
    public var meetingSilenceStopSeconds = 60
    public static let meetingSilenceStopChoices = [0, 60, 120, 300]
    public var voice = VoiceSettings()
    public var pricingOverrides: [String: Double] = [:]
    public var usage: [String: DayUsage] = [:]
    public var historyRetentionDays = 7
    public var idleStopSeconds = 60
    public var toggleMaxSeconds = 300
    public var speechModelPrompted = false
    public var vocabulary: [String] = []
    public var profiles: [Profile] = []
    public var corrections: [CorrectionRule] = []
    public var correctionTally: [CorrectionTallyEntry] = []
    public var timelineSidebarFolded = false
    /// Words a minute, the typing speed every "saved typing" figure is measured against.
    public var typingWPM = 40
    public static let typingWPMRange = 10...120
    public var extra: [String: JSONValue] = [:]

    public init() {}

    /// Applies the bounds and uniqueness rules of design §5.3.
    public func validated() -> Config {
        var validated = self
        validated.historyRetentionDays = historyRetentionDays.clamped(to: 0...30)
        validated.idleStopSeconds = idleStopSeconds.clamped(to: 10...600)
        validated.toggleMaxSeconds = toggleMaxSeconds.clamped(to: 60...1800)
        validated.typingWPM = typingWPM.clamped(to: Self.typingWPMRange)
        if !Self.meetingSilenceStopChoices.contains(meetingSilenceStopSeconds) {
            validated.meetingSilenceStopSeconds = 60
        }
        validated.voice = voice.validated()
        var claimed: Set<String> = []
        validated.profiles = profiles.map { profile in
            var profile = profile
            profile.bundleIDs = profile.bundleIDs.filter { claimed.insert($0).inserted }
            return profile
        }
        // R4: normalise every phrase, drop the unusable, and keep the first of two
        // rules that would fire on the same phrase in the same scope.
        var claimedPhrases: Set<[String?]> = []
        validated.corrections = corrections.compactMap { rule in
            var rule = rule
            rule.heard = PhraseKey.normalised(rule.heard)
            rule.write = PhraseKey.normalised(rule.write)
            rule.soundsLike = rule.soundsLike.map(PhraseKey.normalised).filter { !$0.isEmpty }
            guard !rule.heard.isEmpty, !rule.write.isEmpty else { return nil }
            guard claimedPhrases.insert([rule.bundleID, PhraseKey.key(rule.heard)]).inserted else {
                return nil
            }
            return rule
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
        static let overlayStyle = "overlay_style"
        static let theme = "theme"
        static let updateChannel = "update_channel"
        static let mainWindowFrame = "main_window_frame"
        static let pricingOverrides = "pricing_overrides"
        static let usage = "usage"
        static let historyRetentionDays = "history_retention_days"
        static let idleStopSeconds = "idle_stop_seconds"
        static let toggleMaxSeconds = "toggle_max_seconds"
        static let speechModelPrompted = "speech_model_prompted"
        static let vocabulary = "vocabulary"
        static let profiles = "profiles"
        static let corrections = "corrections"
        static let correctionTally = "correction_tally"
        static let meetingHotkey = "meeting_hotkey"
        static let meetingEngine = "meeting_engine"
        static let meetingKeepAudio = "meeting_keep_audio"
        static let meetingUserName = "meeting_user_name"
        static let meetingSystemAudioExplained = "meeting_system_audio_explained"
        static let meetingNamingEnabled = "meeting_naming_enabled"
        static let meetingNamingAutoApply = "meeting_naming_auto_apply"
        static let meetingUserNameAliases = "meeting_user_name_aliases"
        static let meetingNamingExplained = "meeting_naming_explained"
        static let meetingSilenceStopSeconds = "meeting_silence_stop_seconds"
        static let voiceLocalEnabled = "voice_local_enabled"
        static let voiceSpeechmaticsEnabled = "voice_speechmatics_enabled"
        static let voiceSureThreshold = "voice_sure_threshold"
        static let voiceSuggestThreshold = "voice_suggest_threshold"
        static let voiceMargin = "voice_margin"
        static let voiceMinSpeechSeconds = "voice_min_speech_seconds"
        static let voiceBufferSeconds = "voice_buffer_seconds"
        static let voiceSpeechmaticsSensitivity = "voice_speechmatics_sensitivity"
        static let timelineSidebarFolded = "timeline_sidebar_folded"
        static let typingWPM = "typing_wpm"

        static func voice(_ field: VoiceSettings.Field) -> String {
            switch field {
            case .sure: voiceSureThreshold
            case .suggestion: voiceSuggestThreshold
            case .margin: voiceMargin
            case .minimumSpeech: voiceMinSpeechSeconds
            case .buffer: voiceBufferSeconds
            case .sensitivity: voiceSpeechmaticsSensitivity
            }
        }

        static let all: Set<String> = [
            hotkey, submitHotkey, cleanupEnabled, soundVolume, streamingEnabled, streamingEngine,
            pricingOverrides, usage, historyRetentionDays, idleStopSeconds, toggleMaxSeconds,
            speechModelPrompted, vocabulary, profiles, corrections, correctionTally,
            overlayStyle, meetingHotkey, meetingEngine, meetingKeepAudio, meetingUserName,
            meetingSystemAudioExplained, meetingSilenceStopSeconds, theme, updateChannel, mainWindowFrame,
            meetingNamingEnabled, meetingNamingAutoApply, meetingUserNameAliases, meetingNamingExplained,
            voiceLocalEnabled, voiceSpeechmaticsEnabled, voiceSureThreshold, voiceSuggestThreshold,
            voiceMargin, voiceMinSpeechSeconds, voiceBufferSeconds, voiceSpeechmaticsSensitivity,
            timelineSidebarFolded, typingWPM,
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
        if let value: [CorrectionRule] = try value(Key.corrections) { corrections = value }
        if let value: [CorrectionTallyEntry] = try value(Key.correctionTally) { correctionTally = value }
        if let value: String = try value(Key.meetingHotkey) { meetingHotkey = value }
        if let value: Bool = try value(Key.meetingKeepAudio) { meetingKeepAudio = value }
        meetingUserName = try value(Key.meetingUserName)
        if let value: Bool = try value(Key.meetingSystemAudioExplained) { meetingSystemAudioExplained = value }
        if let value: Bool = try value(Key.meetingNamingEnabled) { meetingNamingEnabled = value }
        if let value: Bool = try value(Key.meetingNamingAutoApply) { meetingNamingAutoApply = value }
        if let value: [String] = try value(Key.meetingUserNameAliases) { meetingUserNameAliases = value }
        if let value: Bool = try value(Key.meetingNamingExplained) { meetingNamingExplained = value }

        let engine: String? = try value(Key.streamingEngine)
        streamingEngine = engine.flatMap(EngineName.init(rawValue:))
        // A value this build does not know — written by a newer one, or by hand. It is
        // ignored at runtime (F32 picks the platform default) but kept so saving here
        // does not destroy it (F2).
        unrecognisedStreamingEngine = streamingEngine == nil ? engine : nil

        let meeting: String? = try value(Key.meetingEngine)
        meetingEngine = meeting.flatMap(MeetingEngine.init(rawValue:))
        unrecognisedMeetingEngine = meetingEngine == nil ? meeting : nil

        let style: String? = try value(Key.overlayStyle)
        let known = style.flatMap(OverlayStyle.init(rawValue:))
        overlayStyle = known ?? .default
        unrecognisedOverlayStyle = known == nil ? style : nil

        let rawTheme: String? = try value(Key.theme)
        let knownTheme = rawTheme.flatMap(AppTheme.init(rawValue:))
        theme = knownTheme ?? .system
        unrecognisedTheme = knownTheme == nil ? rawTheme : nil

        let rawChannel: String? = try value(Key.updateChannel)
        let knownChannel = rawChannel.flatMap(UpdateChannel.init(rawValue:))
        updateChannel = knownChannel ?? .release
        unrecognisedUpdateChannel = knownChannel == nil ? rawChannel : nil

        // `try?`: a throw here would have `ConfigStore` back the whole file up as corrupt
        // over a value that only places a window.
        mainWindowFrame = try? value(Key.mainWindowFrame)
        // `try?` for the same reason: a wrong-typed threshold reads as the default.
        if let value: Int = try? value(Key.meetingSilenceStopSeconds) { meetingSilenceStopSeconds = value }
        if let value: Bool = try? value(Key.voiceLocalEnabled) { voice.localEnabled = value }
        if let value: Bool = try? value(Key.voiceSpeechmaticsEnabled) { voice.speechmaticsEnabled = value }
        for field in VoiceSettings.Field.allCases {
            if let value: Double = try? value(Key.voice(field)) {
                voice[keyPath: VoiceSettings.keyPath(of: field)] = value
            }
        }
        if let value: Bool = try? value(Key.timelineSidebarFolded) { timelineSidebarFolded = value }
        if let value: Int = try? value(Key.typingWPM) { typingWPM = value }

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
        try container.encode(corrections, forKey: AnyCodingKey(Key.corrections))
        try container.encode(correctionTally, forKey: AnyCodingKey(Key.correctionTally))
        try container.encode(
            unrecognisedOverlayStyle ?? overlayStyle.rawValue,
            forKey: AnyCodingKey(Key.overlayStyle)
        )
        try container.encode(unrecognisedTheme ?? theme.rawValue, forKey: AnyCodingKey(Key.theme))
        try container.encode(
            unrecognisedUpdateChannel ?? updateChannel.rawValue,
            forKey: AnyCodingKey(Key.updateChannel)
        )
        try container.encodeIfPresent(mainWindowFrame, forKey: AnyCodingKey(Key.mainWindowFrame))
        try container.encode(meetingHotkey, forKey: AnyCodingKey(Key.meetingHotkey))
        if let meetingEngine {
            try container.encode(meetingEngine, forKey: AnyCodingKey(Key.meetingEngine))
        } else if let unrecognisedMeetingEngine {
            try container.encode(unrecognisedMeetingEngine, forKey: AnyCodingKey(Key.meetingEngine))
        }
        try container.encode(meetingKeepAudio, forKey: AnyCodingKey(Key.meetingKeepAudio))
        try container.encodeIfPresent(meetingUserName, forKey: AnyCodingKey(Key.meetingUserName))
        try container.encode(
            meetingSystemAudioExplained, forKey: AnyCodingKey(Key.meetingSystemAudioExplained)
        )
        try container.encode(meetingNamingEnabled, forKey: AnyCodingKey(Key.meetingNamingEnabled))
        try container.encode(meetingNamingAutoApply, forKey: AnyCodingKey(Key.meetingNamingAutoApply))
        try container.encode(meetingUserNameAliases, forKey: AnyCodingKey(Key.meetingUserNameAliases))
        try container.encode(meetingNamingExplained, forKey: AnyCodingKey(Key.meetingNamingExplained))
        try container.encode(meetingSilenceStopSeconds, forKey: AnyCodingKey(Key.meetingSilenceStopSeconds))
        try container.encode(voice.localEnabled, forKey: AnyCodingKey(Key.voiceLocalEnabled))
        try container.encode(voice.speechmaticsEnabled, forKey: AnyCodingKey(Key.voiceSpeechmaticsEnabled))
        for field in VoiceSettings.Field.allCases {
            try container.encode(voice.value(of: field), forKey: AnyCodingKey(Key.voice(field)))
        }
        try container.encode(timelineSidebarFolded, forKey: AnyCodingKey(Key.timelineSidebarFolded))
        try container.encode(typingWPM, forKey: AnyCodingKey(Key.typingWPM))

        for (key, value) in extra where !Key.all.contains(key) {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension JSONValue {
    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}
