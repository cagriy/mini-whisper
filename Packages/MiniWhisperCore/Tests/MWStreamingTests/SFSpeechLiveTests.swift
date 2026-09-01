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
        while true {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
            try file.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            engine.feed(buffer)
        }

        let result = await engine.finish(timeout: .seconds(15))

        #expect(result.ok)
        #expect(result.text.isEmpty == false)
        #expect(sink.errors.isEmpty)
    }
}
