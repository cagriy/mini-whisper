import AVFAudio
import Foundation
import MWTestSupport
import Testing

import MWAudio

/// Starts a real process tap, so it is opt-in only: a plain `swift test` skips it.
/// Command: `MW_INTEGRATION=1 swift test --filter SystemAudioTapIntegrationTests` on macOS 14.2+.
/// The terminal running it needs System Audio Recording permission; without it the tap
/// delivers silence and the test times out.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1"))
struct SystemAudioTapIntegrationTests {
    private struct Level: Sendable {
        let rms: Float
        let sampleRate: Double
        let channels: AVAudioChannelCount
    }

    @available(macOS 14.2, *)
    @Test func tapDeliversBuffersOn142() async throws {
        let tap = SystemAudioTap(excluding: getpid())
        let (levels, continuation) = AsyncStream<Level>.makeStream()
        try tap.start { buffer in
            continuation.yield(Level(rms: Self.rms(buffer), sampleRate: buffer.format.sampleRate, channels: buffer.format.channelCount))
        }
        defer { tap.stop() }

        // Played from a child process: the tap leaves out this process's own audio.
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [try TestFixtures.wav("filler_words").path]
        try player.run()
        defer { player.terminate() }

        let loud = await withTaskGroup(of: Level?.self) { group in
            group.addTask {
                // −60 dBFS.
                for await level in levels where level.rms > 0.001 { return level }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        let level = try #require(loud)
        #expect(level.sampleRate == 16000)
        #expect(level.channels == 1)
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        return (sum / Float(count)).squareRoot()
    }
}
