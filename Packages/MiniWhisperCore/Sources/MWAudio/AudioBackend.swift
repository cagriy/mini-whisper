import AVFAudio

public protocol AudioBackend: Sendable {
    var inputFormat: AVAudioFormat { get }
    var events: AsyncStream<AudioBackendEvent> { get }
    func start() throws
    func stop()
    func installTap(bufferSize: AVAudioFrameCount, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void)
}
