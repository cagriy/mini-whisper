import MWConfig
import MWTranscription

/// The summary and naming client bound to whatever key the Keychain holds at call time, like
/// `KeyedOpenAIClient`, so a key saved in Settings applies without a relaunch.
struct KeyedAnthropicClient: Summarizing, NameSuggesting {
    let secrets: any SecretStore

    func summarise(system: String, user: String) async throws -> SummaryResult {
        try await client().summarise(system: system, user: user)
    }

    func suggestNames(_ request: NamingRequest) async throws -> NamingReply {
        try await client().suggestNames(request)
    }

    private func client() throws -> AnthropicClient {
        guard let key = try secrets.secret(for: .anthropic), !key.isEmpty else { throw MissingAPIKey() }
        return AnthropicClient(apiKey: key)
    }
}
