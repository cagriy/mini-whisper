import Foundation
import MWTestSupport
import Testing

import MWTranscription

/// Opt-in: needs the network and a live OpenAI key, so a plain `swift test` skips it.
/// Command: `MW_INTEGRATION=1 OPENAI_API_KEY=… swift test --filter OpenAIIntegrationTests`.
private let liveKey: String? = {
    guard ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1",
        let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty
    else { return nil }
    return key
}()

@Suite struct OpenAIIntegrationTests {
    @Test(
        .enabled(if: liveKey != nil),
        arguments: ["filler_words", "self_corrections", "filler_and_corrections"]
    )
    func transcribesAndCleansEachFixture(_ fixture: String) async throws {
        let client = OpenAIClient(apiKey: try #require(liveKey))
        let wav = try Data(contentsOf: try TestFixtures.wav(fixture))

        let (raw, transcribeUsage) = try await client.transcribe(
            wav: wav,
            prompt: "Transcribe the audio verbatim."
        )
        #expect(!raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(transcribeUsage.inputTokens > 0)

        let (cleaned, cleanUsage) = try await client.clean(
            raw,
            prompt: "Remove filler words and false starts. Return only the cleaned text."
        )
        #expect(!cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(cleanUsage.inputTokens > 0)
    }
}
