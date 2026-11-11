import MWMeetings

/// One bundled test-call script (design §5.2). Runs compare only within the same `id` and
/// `revision`, so any change to a line bumps the revision.
public struct TestScenario: Sendable, Equatable, Identifiable {
    public var id: String
    public var revision: Int
    public var title: String
    /// Roles `.a` and `.b`.
    public var voices: [VoiceRole]
    public var lines: [ScenarioLine]

    public init(id: String, revision: Int, title: String, voices: [VoiceRole], lines: [ScenarioLine]) {
        self.id = id
        self.revision = revision
        self.title = title
        self.voices = voices
        self.lines = lines
    }
}

/// A synthetic speaker of a scenario.
public struct VoiceRole: Sendable, Equatable {
    public var role: TestCallRole
    public var character: String
    /// A macOS voice name, as `say -v ?` lists it.
    public var requested: String

    public init(role: TestCallRole, character: String, requested: String) {
        self.role = role
        self.character = character
        self.requested = requested
    }
}

public struct ScenarioLine: Sendable, Equatable {
    public var role: TestCallRole
    /// The reference text, spoken as written by `say` or read aloud by the user.
    public var text: String

    public init(role: TestCallRole, text: String) {
        self.role = role
        self.text = text
    }
}

public enum ScenarioChoice: Sendable, Hashable {
    case random
    /// A scenario id.
    case named(String)
}

/// What the player hands to `say`.
public struct VoiceLine: Sendable, Equatable {
    public var text: String
    public var voice: String

    public init(text: String, voice: String) {
        self.text = text
        self.voice = voice
    }
}

/// The voice a role plays with on this Mac; `voice` differs from `requested` when substituted.
public struct CastVoice: Sendable, Equatable {
    public var role: TestCallRole
    public var character: String
    public var requested: String
    public var voice: String

    public init(role: TestCallRole, character: String, requested: String, voice: String) {
        self.role = role
        self.character = character
        self.requested = requested
        self.voice = voice
    }
}

public enum VoiceCasting: Sendable, Equatable {
    /// Keyed by `.a` and `.b`.
    case ready([TestCallRole: CastVoice])
    /// Fewer than two distinct English voices are installed.
    case unavailable
}
