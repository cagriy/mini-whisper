import MWMeetings

/// What the conductor records of one test call; the scorer reads it at Stop.
public struct TestCallRun: Sendable, Equatable {
    /// One per script line, in script order.
    public var lines: [RunLine]
    /// Keyed by `.a` and `.b`.
    public var casting: [TestCallRole: CastVoice]
    public var overlap: Bool

    public init(lines: [RunLine], casting: [TestCallRole: CastVoice], overlap: Bool) {
        self.lines = lines
        self.casting = casting
        self.overlap = overlap
    }
}

/// One script line's outcome. Times are meeting seconds.
public struct RunLine: Sendable, Equatable {
    /// The 1-based script line number, as the record and the Script pane number lines.
    public var index: Int
    public var role: TestCallRole
    public var status: TestCallLineStatus
    /// A voice line's `say` launch, or the user's first speech after the prompt.
    public var start: Double?
    /// A voice line's `say` exit, or the end of the user's last speech before the hand-over.
    public var end: Double?
    /// Set on a user line and the voice line that started during it.
    public var overlapped: Bool
    /// Set when `status` is `.skipped`.
    public var skipReason: SkipReason?

    public init(
        index: Int,
        role: TestCallRole,
        status: TestCallLineStatus = .notReached,
        start: Double? = nil,
        end: Double? = nil,
        overlapped: Bool = false,
        skipReason: SkipReason? = nil
    ) {
        self.index = index
        self.role = role
        self.status = status
        self.start = start
        self.end = end
        self.overlapped = overlapped
        self.skipReason = skipReason
    }
}

/// Why the script ended early.
public enum EndReason: Sendable {
    case stop
    case sleep
}

/// Why a line was skipped. The raw value is what the log says.
public enum SkipReason: String, Sendable {
    /// The Skip line button.
    case skipped = "skip"
    /// No speech within 20 s of the prompt.
    case noSpeech = "no speech"
    /// `say` failed to launch or exited non-zero.
    case voiceFailed = "voice failed"
}

/// What the Script pane follows. Line numbers are 1-based.
public enum ConductorEvent: Sendable, Equatable {
    public enum Turn: Sendable, Equatable {
        case voiceSpeaking(TestCallRole)
        case yourTurn
    }

    case line(Int, Turn)
    case skipped(Int, SkipReason)
    /// The tap heard nothing since this voice line started (design §5.6).
    case captureMissing(Int)
    /// Two `say` runs failed in a row; `.finished` follows.
    case voicesFailed
    case finished
}

/// One `say` run, in meeting seconds.
public struct Playback: Sendable, Equatable {
    public var launched: Double
    public var exited: Double
    /// False when `say` failed to launch, exited non-zero or was stopped.
    public var normalExit: Bool

    public init(launched: Double, exited: Double, normalExit: Bool) {
        self.launched = launched
        self.exited = exited
        self.normalExit = normalExit
    }
}

/// Plays voice lines through `say`.
@MainActor
public protocol SpeechPlaying {
    /// Returns once the process has exited, or failed to launch.
    func play(_ line: VoiceLine) async -> Playback
    /// Terminates the running `say`; its `play` then returns with `normalExit == false`.
    func stop()
}

/// The meeting's clock, microphone speech and system-audio tap, as the conductor reads them.
@MainActor
public protocol UserSpeechSensing {
    var meetingTime: Double { get }
    var isSpeaking: Bool { get }
    /// Microphone speech in meeting seconds, in time order; the open span last.
    var speechSpans: [ClosedRange<Double>] { get }
    /// The meeting time of the latest tick whose system audio was audible.
    var lastAudibleSystemAudio: Double? { get }
}
