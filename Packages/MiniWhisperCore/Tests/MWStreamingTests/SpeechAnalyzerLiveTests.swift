import AVFAudio
import Foundation
import MWSupport
import MWTestSupport
import Testing

import MWStreaming

/// The platform-only remainder of Stage 13: `SpeechAnalyzerBridge` against the real
/// `SpeechAnalyzer`. Needs macOS 26 and the installed speech model, so it is opt-in
/// and never part of a plain `swift test`.
///
///     MW_INTEGRATION=1 swift test --filter SpeechAnalyzerLiveTests
@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1"
        && ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ))
)
struct SpeechAnalyzerLiveTests {
    @Test func transcribesFixtureWav() async throws {
        let api = SpeechAnalyzerBridge()
        try #require(api.isAvailable)
        guard await SpeechModelAssets.status(api: api, locale: .current) == .installed else {
            Issue.record("the on-device speech model is not installed — install it from Settings, then re-run")
            return
        }

        let engine = SpeechAnalyzerEngine(api: api)
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
