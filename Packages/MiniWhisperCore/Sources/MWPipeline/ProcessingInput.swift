import MWAudio
import MWConfig
import MWCorrections
import MWHotkeys
import MWProfiles
import MWStreaming

/// One stopped recording, with everything resolved at release time (design §5.5).
/// `config` is read at release and `snapshot` taken at press: the job re-reads neither.
public struct ProcessingInput: Sendable {
    public var recording: Recording
    public var engine: (any StreamingEngine)?
    public var sink: StreamSink?
    public var profile: ResolvedProfile
    public var target: PasteTarget
    public var binding: BindingName
    public var config: Config
    /// R12: the rules and vocabulary taken at press, not re-read here.
    public var snapshot: CorrectionSnapshot

    public init(
        recording: Recording,
        engine: (any StreamingEngine)?,
        sink: StreamSink?,
        profile: ResolvedProfile,
        target: PasteTarget,
        binding: BindingName,
        config: Config,
        snapshot: CorrectionSnapshot
    ) {
        self.recording = recording
        self.engine = engine
        self.sink = sink
        self.profile = profile
        self.target = target
        self.binding = binding
        self.config = config
        self.snapshot = snapshot
    }
}
