import MWAudio
import MWConfig
import MWHistory
import MWPaste
import MWStreaming
import MWTranscription
import MWUsage

/// `prompt.txt` / `transcribe_prompt.txt` behind a seam, so the pipeline can be exercised
/// without a config directory. `MWConfig.PromptFiles` is the production implementation.
public protocol PromptProviding: Sendable {
    func transcribeInstructions() throws -> String
    func cleanupPrompt() throws -> String
}

extension PromptFiles: PromptProviding {}

/// Every side effect the pipeline has, protocol-typed so the whole state machine is
/// testable with fakes (design §5.2).
public struct Dependencies: Sendable {
    public var audio: any AudioCapture
    public var engines: any EngineProvider
    public var frontmost: any FrontmostAppProviding
    public var transcriber: any Transcriber
    public var cleaner: any Cleaner
    public var paster: any Pasting
    public var secrets: any SecretStore
    public var usage: any UsageRecording
    public var history: any HistoryRecording
    public var sounds: any SoundPlaying
    public var prompts: any PromptProviding

    public init(
        audio: any AudioCapture,
        engines: any EngineProvider,
        frontmost: any FrontmostAppProviding,
        transcriber: any Transcriber,
        cleaner: any Cleaner,
        paster: any Pasting,
        secrets: any SecretStore,
        usage: any UsageRecording,
        history: any HistoryRecording,
        sounds: any SoundPlaying,
        prompts: any PromptProviding
    ) {
        self.audio = audio
        self.engines = engines
        self.frontmost = frontmost
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.paster = paster
        self.secrets = secrets
        self.usage = usage
        self.history = history
        self.sounds = sounds
        self.prompts = prompts
    }
}
