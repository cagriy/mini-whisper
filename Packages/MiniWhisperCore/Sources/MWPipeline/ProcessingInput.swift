import MWAudio
import MWConfig
import MWHotkeys
import MWProfiles
import MWStreaming

/// One stopped recording, with everything resolved at release time (design §5.5).
/// `config` is the snapshot taken at release: the job never re-reads it mid-flight.
public struct ProcessingInput: Sendable {
    public var recording: Recording
    public var engine: (any StreamingEngine)?
    public var sink: StreamSink?
    public var profile: ResolvedProfile
    public var target: PasteTarget
    public var binding: BindingName
    public var config: Config

    public init(
        recording: Recording,
        engine: (any StreamingEngine)?,
        sink: StreamSink?,
        profile: ResolvedProfile,
        target: PasteTarget,
        binding: BindingName,
        config: Config
    ) {
        self.recording = recording
        self.engine = engine
        self.sink = sink
        self.profile = profile
        self.target = target
        self.binding = binding
        self.config = config
    }
}
