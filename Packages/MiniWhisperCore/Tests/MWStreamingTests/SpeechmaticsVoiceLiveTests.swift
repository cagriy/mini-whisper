import Foundation
import MWConfig
import MWTestSupport
import Testing

import MWStreaming

/// Design §5 Testing, Integration: Speechmatics enrols a voice it identified in one session and
/// names it by its `mw:` label in the next. Spends the user's own credits, so it is opt-in and
/// reads the key from the environment only.
///
///     MW_INTEGRATION=1 SPEECHMATICS_API_KEY=… swift test --filter SpeechmaticsVoiceLiveTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1"))
struct SpeechmaticsVoiceLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPEECHMATICS_API_KEY"] != nil))
    func enrolThenRecognise() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["SPEECHMATICS_API_KEY"])
        let label = "mw:" + UUID().uuidString.lowercased()

        let first = try await play(key: key, voices: VoiceSessionConfig(speakers: [], sensitivity: 0.8))
        let identifier = try #require(
            first.speakers.flatMap { $0 }.first { $0.label == "S1" }?.identifiers.first,
            "no SpeakersResult for S1"
        )

        let second = try await play(
            key: key,
            voices: VoiceSessionConfig(
                speakers: [VoiceSessionConfig.Speaker(label: label, identifier: identifier)],
                sensitivity: 0.8
            )
        )

        #expect(second.ignored.isEmpty)
        #expect(second.segments.contains { $0.speaker == label })
    }

    private func play(key: String, voices: VoiceSessionConfig) async throws -> RecordingSink {
        let sink = RecordingSink()
        let result = try await ClipPlayback.play(
            try TestFixtures.wav("two_speakers"),
            through: EngineFactory().makeMeeting(.speechmaticsStandard, key: key, hints: .none, voices: voices),
            sink: sink,
            timeout: .seconds(30),
            realTime: true
        )
        #expect(result.ok)
        #expect(sink.errors.isEmpty)
        return sink
    }
}
