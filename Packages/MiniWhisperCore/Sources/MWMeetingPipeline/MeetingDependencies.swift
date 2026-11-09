import Foundation
import MWAudio
import MWConfig
import MWMeetings
import MWStreaming
import MWSupport
import MWTranscription
import MWUsage

/// Every side effect a meeting has, protocol-typed so the controller runs on fakes (design §5.3).
public struct MeetingDependencies: Sendable {
    public var audio: any AudioCapture
    /// Returns nil below macOS 14.2, where a remote meeting runs on the microphone alone.
    public var tapFactory: any SystemAudioTapFactory
    public var engines: any MeetingEngineProviding
    public var secrets: any SecretStore
    public var store: MeetingStore
    public var summarizer: any Summarizing
    public var usage: any UsageRecording
    public var prompts: any SummaryPromptProviding
    /// The app that was frontmost when the chooser opened.
    public var frontAppName: @Sendable () -> String?
    /// The user's label when `meeting_user_name` is unset: the account's full name.
    public var userName: @Sendable () -> String
    public var clock: any Clock
    /// Wall time for `startedAt`, `endedAt` and note and summary stamps.
    public var now: @Sendable () -> Date
    /// Opens `audio.m4a` when `meeting_keep_audio` is on.
    public var makeAudioWriter: @Sendable (URL) throws -> any AudioFileWriting

    public init(
        audio: any AudioCapture,
        tapFactory: any SystemAudioTapFactory,
        engines: any MeetingEngineProviding,
        secrets: any SecretStore,
        store: MeetingStore,
        summarizer: any Summarizing,
        usage: any UsageRecording,
        prompts: any SummaryPromptProviding,
        frontAppName: @escaping @Sendable () -> String?,
        userName: @escaping @Sendable () -> String,
        clock: any Clock = SystemClock(),
        now: @escaping @Sendable () -> Date = { Date() },
        makeAudioWriter: @escaping @Sendable (URL) throws -> any AudioFileWriting = { try AACFileWriter(url: $0) }
    ) {
        self.audio = audio
        self.tapFactory = tapFactory
        self.engines = engines
        self.secrets = secrets
        self.store = store
        self.summarizer = summarizer
        self.usage = usage
        self.prompts = prompts
        self.frontAppName = frontAppName
        self.userName = userName
        self.clock = clock
        self.now = now
        self.makeAudioWriter = makeAudioWriter
    }
}
