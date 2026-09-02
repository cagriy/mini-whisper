import Foundation
import MWConfig
import MWSupport
import MWTranscription

/// The batch client bound to whatever key the Keychain holds at call time, so a key
/// saved in Settings applies without a relaunch. `KeychainStore` caches the read (§5.9).
struct KeyedOpenAIClient: Transcriber, Cleaner {
    let secrets: any SecretStore

    func transcribe(wav: Data, instructions: String) async throws -> (String, TokenUsage) {
        try await client().transcribe(wav: wav, instructions: instructions)
    }

    func clean(_ text: String, prompt: String) async throws -> (String, TokenUsage) {
        try await client().clean(text, prompt: prompt)
    }

    private func client() throws -> OpenAIClient {
        guard let key = try secrets.secret(for: .openai), !key.isEmpty else {
            throw MissingAPIKey()
        }
        return OpenAIClient(apiKey: key)
    }
}

/// F13's message, for the race where the key disappears after the pipeline's own check.
struct MissingAPIKey: LocalizedError {
    var errorDescription: String? { "No API key configured" }
}
