import AVFAudio
import Foundation
import MWSupport
import MWTestSupport
import Testing

import MWStreaming

/// The platform-only remainder of Stage 12: `SFSpeechRecognitionBridge` against the
/// real recogniser. Needs the Speech Recognition TCC grant, so it is opt-in and never
/// part of a plain `swift test`.
///
///     MW_INTEGRATION=1 swift test --filter SFSpeechLiveTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1"))
struct SFSpeechLiveTests {
    @Test func transcribesFixtureWavOnDevice() async throws {
        let api = SFSpeechRecognitionBridge()
        try #require(SpeechPermission.ensureAuthorized(api: api) == .authorized)

        let engine = SFSpeechEngine(api: api)
        let sink = RecordingSink()
        engine.start(sink: sink)

        let file = try AVAudioFile(forReading: TestFixtures.wav("filler_words"))
        // Bounded by framePosition: on macOS 26 a read at end-of-file throws
        // _GenericObjCError.nilError instead of returning zero frames.
        while file.framePosition < file.length {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
            let remaining = AVAudioFrameCount(file.length - file.framePosition)
            try file.read(into: buffer, frameCount: min(4096, remaining))
            guard buffer.frameLength > 0 else { break }
            engine.feed(buffer)
        }

        let result = await engine.finish(timeout: .seconds(15))

        #expect(result.ok)
        #expect(result.text.isEmpty == false)
        #expect(sink.errors.isEmpty)
    }
}
