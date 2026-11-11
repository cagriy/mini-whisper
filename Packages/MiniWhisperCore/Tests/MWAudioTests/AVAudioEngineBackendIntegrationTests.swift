import AVFAudio
import Foundation
import Testing

@testable import MWAudio

/// Hands each phase of a test the first buffer delivered after it starts waiting.
private final class BufferProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Int>.Continuation?

    func deliver(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { continuation }?.yield(Int(buffer.frameLength))
    }

    /// Frames in the next buffer, or nil when none arrives before the deadline.
    func nextBuffer(within deadline: Duration) async -> Int? {
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        lock.withLock { self.continuation = continuation }
        return await withTaskGroup(of: Int?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// Opens the real microphone, so it is opt-in only: a plain `swift test` skips it.
/// Command: `MW_INTEGRATION=1 swift test --filter AVAudioEngineBackendIntegrationTests`
/// (prompts once for the Microphone permission).
/// Serialized: the tests share one microphone, and voice processing changes its input format
/// under any engine running at the same time.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1"))
struct AVAudioEngineBackendIntegrationTests {
    @Test func deliversABufferWithinOneSecond() async throws {
        let backend = AVAudioEngineBackend()
        let (buffers, continuation) = AsyncStream<Int>.makeStream()
        backend.installTap(bufferSize: 1024) { buffer in
            continuation.yield(Int(buffer.frameLength))
        }
        #expect(backend.inputFormat.sampleRate > 0)

        try backend.start()
        defer { backend.stop() }

        let frames = await withTaskGroup(of: Int?.self) { group in
            group.addTask {
                var iterator = buffers.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(1))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        #expect(frames ?? 0 > 0)
    }

    /// Voice processing can only change while the engine is stopped and can change the
    /// input format, so the backend restarts and reinstalls the tap around it.
    @Test func voiceProcessingTogglesAndBuffersKeepFlowing() async throws {
        let backend = AVAudioEngineBackend()
        let probe = BufferProbe()
        backend.installTap(bufferSize: 1024) { probe.deliver($0) }
        try backend.start()
        defer {
            try? backend.setVoiceProcessing(false)
            backend.stop()
        }
        #expect(await probe.nextBuffer(within: .seconds(5)) ?? 0 > 0)

        try backend.setVoiceProcessing(true)
        #expect(await probe.nextBuffer(within: .seconds(5)) ?? 0 > 0)

        try backend.setVoiceProcessing(false)
        #expect(await probe.nextBuffer(within: .seconds(5)) ?? 0 > 0)
    }

    /// Default ducking turned other apps' audio, the tap's copy of the call included, down ~30 dB.
    @Test func voiceProcessingDucksOtherAudioOnlyMinimally() throws {
        let backend = AVAudioEngineBackend()
        defer { try? backend.setVoiceProcessing(false) }
        try backend.setVoiceProcessing(true)
        let ducking = backend.otherAudioDucking
        #expect(ducking.enableAdvancedDucking.boolValue)
        #expect(ducking.duckingLevel == .min)
    }
}
