import Foundation
import MWConfig
import MWTestSupport
import Testing

import MWStreaming

/// Design §5.12 Integration: each provider diarizes the synthesised two-voice fixture
/// through `makeMeeting`. Two distinct labels prove the diarization parameters were
/// honoured — AssemblyAI ignores a misspelt one silently. Spends the user's own
/// credits, so it is opt-in and reads keys from the environment only.
///
///     MW_INTEGRATION=1 SPEECHMATICS_API_KEY=… ASSEMBLYAI_API_KEY=… swift test --filter MeetingEngineLiveTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1"))
struct MeetingEngineLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPEECHMATICS_API_KEY"] != nil))
    func speechmaticsDiarizesTwoSpeakers() async throws {
        try await expectTwoSpeakers(.speechmaticsStandard, keyVariable: "SPEECHMATICS_API_KEY")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASSEMBLYAI_API_KEY"] != nil))
    func assemblyAIDiarizesTwoSpeakers() async throws {
        try await expectTwoSpeakers(.assemblyaiStreaming, keyVariable: "ASSEMBLYAI_API_KEY")
    }

    private func expectTwoSpeakers(_ tier: MeetingEngine, keyVariable: String) async throws {
        let key = try #require(ProcessInfo.processInfo.environment[keyVariable])
        let sink = RecordingSink()

        let result = try await ClipPlayback.play(
            try TestFixtures.wav("two_speakers"),
            through: EngineFactory().makeMeeting(tier, key: key, hints: .none),
            sink: sink,
            timeout: .seconds(30),
            realTime: true
        )

        #expect(result.ok)
        #expect(sink.errors.isEmpty)
        #expect(Set(sink.segments.compactMap(\.speaker)).count >= 2)
        #expect(sink.segments.contains { !$0.text.isEmpty })
    }
}
