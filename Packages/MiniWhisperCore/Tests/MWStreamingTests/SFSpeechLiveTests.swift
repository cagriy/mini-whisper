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

        let sink = RecordingSink()
        let result = try await ClipPlayback.play(
            try TestFixtures.wav("filler_words"),
            through: SFSpeechEngine(api: api),
            sink: sink,
            timeout: .seconds(15)
        )

        #expect(result.ok)
        #expect(result.text.isEmpty == false)
        #expect(sink.errors.isEmpty)
    }
}
