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

        let sink = RecordingSink()
        let result = try await ClipPlayback.play(
            try TestFixtures.wav("filler_words"),
            through: SpeechAnalyzerEngine(api: api),
            sink: sink,
            timeout: .seconds(15)
        )

        #expect(result.ok)
        #expect(result.text.isEmpty == false)
        #expect(sink.errors.isEmpty)
    }
}
