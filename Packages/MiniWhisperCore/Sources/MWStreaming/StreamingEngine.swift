import AVFAudio
import MWConfig

/// The engine seam every live-transcript backend implements (F20).
public protocol StreamingEngine: AnyObject, Sendable {
    var name: EngineName { get }
    /// Begins the session; never blocks the caller.
    func start(sink: any TranscriptSink)
    /// Called synchronously on the audio tap thread; must not block.
    func feed(_ buffer: AVAudioPCMBuffer)
    /// Flushes, closes and returns the compound result.
    func finish(timeout: Duration) async -> StreamResult
}
