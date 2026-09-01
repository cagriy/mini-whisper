import AVFAudio
import Foundation
import MWAudio

public final class FakeAudioBackend: AudioBackend, @unchecked Sendable {
    public enum Failure: Error, Equatable { case startFailed }

    private struct State {
        var handler: (@Sendable (AVAudioPCMBuffer) -> Void)?
        var startCount = 0
        var stopCount = 0
        var tapBufferSize: AVAudioFrameCount?
        var tapFormat: AVAudioFormat?
        var startError: (any Error)?
    }

    private let lock = NSLock()
    private var state = State()
    private let eventContinuation: AsyncStream<AudioBackendEvent>.Continuation

    public let inputFormat: AVAudioFormat
    public let events: AsyncStream<AudioBackendEvent>

    public init(sampleRate: Double = 48000) {
        inputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        (events, eventContinuation) = AsyncStream.makeStream()
    }

    public var startCount: Int { lock.withLock { state.startCount } }
    public var stopCount: Int { lock.withLock { state.stopCount } }
    public var tapBufferSize: AVAudioFrameCount? { lock.withLock { state.tapBufferSize } }
    public var tapFormat: AVAudioFormat? { lock.withLock { state.tapFormat } }

    public var startError: (any Error)? {
        get { lock.withLock { state.startError } }
        set { lock.withLock { state.startError = newValue } }
    }

    public func start() throws {
        if let error = lock.withLock({ state.startError }) { throw error }
        lock.withLock { state.startCount += 1 }
    }

    public func stop() {
        lock.withLock { state.stopCount += 1 }
    }

    public func installTap(bufferSize: AVAudioFrameCount, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        lock.withLock {
            state.handler = handler
            state.tapBufferSize = bufferSize
            state.tapFormat = inputFormat
        }
    }

    /// Runs the tap handler on the caller's thread, like the real tap does.
    public func deliver(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { state.handler }?(buffer)
    }

    public func emit(_ event: AudioBackendEvent) {
        eventContinuation.yield(event)
    }
}
