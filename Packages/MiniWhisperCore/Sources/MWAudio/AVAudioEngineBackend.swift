import AVFAudio
import AppKit
import Foundation

/// The real `AVAudioEngine` behind `AudioBackend`: one engine, one 1024-frame tap
/// at the hardware input format, plus the two notifications the lifecycle reacts to
/// (F18, F19).
public final class AVAudioEngineBackend: AudioBackend, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let continuation: AsyncStream<AudioBackendEvent>.Continuation
    private let configurationObserver: any NSObjectProtocol
    private let sleepObserver: any NSObjectProtocol

    public let events: AsyncStream<AudioBackendEvent>

    public init() {
        let (stream, continuation) = AsyncStream<AudioBackendEvent>.makeStream()
        events = stream
        self.continuation = continuation
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { _ in continuation.yield(.configurationChanged) }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { _ in continuation.yield(.systemWillSleep) }
    }

    deinit {
        NotificationCenter.default.removeObserver(configurationObserver)
        NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        continuation.finish()
    }

    public var inputFormat: AVAudioFormat { engine.inputNode.inputFormat(forBus: 0) }

    public func start() throws {
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.stop()
    }

    public func installTap(
        bufferSize: AVAudioFrameCount,
        handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: input.inputFormat(forBus: 0)) { buffer, _ in
            handler(buffer)
        }
    }
}
