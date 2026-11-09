import AVFAudio
import AppKit
import Foundation
import os

/// The real `AVAudioEngine` behind `AudioBackend`: one engine, one 1024-frame tap
/// at the hardware input format, plus the two notifications the lifecycle reacts to
/// (F18, F19).
public final class AVAudioEngineBackend: AudioBackend, @unchecked Sendable {
    private let engine = AVAudioEngine()
    /// Kept so a voice-processing change can reinstall the tap at the new input format.
    private let tap = OSAllocatedUnfairLock<(size: AVAudioFrameCount, handler: @Sendable (AVAudioPCMBuffer) -> Void)?>(
        initialState: nil
    )
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
        tap.withLock { $0 = (bufferSize, handler) }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: input.inputFormat(forBus: 0)) { buffer, _ in
            handler(buffer)
        }
    }

    public func setVoiceProcessing(_ on: Bool) throws {
        let input = engine.inputNode
        guard input.isVoiceProcessingEnabled != on else { return }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        // On failure the engine still restarts, without voice processing.
        let applied = Result { try input.setVoiceProcessingEnabled(on) }
        if wasRunning {
            if let tap = tap.withLock({ $0 }) { installTap(bufferSize: tap.size, handler: tap.handler) }
            try start()
        }
        try applied.get()
    }
}
