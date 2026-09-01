import AVFAudio
import Foundation
import Testing

import MWAudio

/// Opens the real microphone, so it is opt-in only: a plain `swift test` skips it.
/// Command: `MW_INTEGRATION=1 swift test --filter AVAudioEngineBackendIntegrationTests`
/// (prompts once for the Microphone permission).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1"))
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
}
