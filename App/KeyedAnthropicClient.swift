import MWConfig
import MWTranscription

/// The summary client bound to whatever key the Keychain holds at call time, like
/// `KeyedOpenAIClient`, so a key saved in Settings applies without a relaunch.
struct KeyedAnthropicClient: Summarizing {
    let secrets: any SecretStore

    func summarise(system: String, user: String) async throws -> SummaryResult {
        guard let key = try secrets.secret(for: .anthropic), !key.isEmpty else { throw MissingAPIKey() }
        return try await AnthropicClient(apiKey: key).summarise(system: system, user: user)
    }
}
