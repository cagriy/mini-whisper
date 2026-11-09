/// The five generic-password accounts the app owns under service `mini-whisper`
/// (F3); the first three match `config.py:KEYRING_USERNAME` / `STREAMING_KEY_USERNAMES`.
public enum KeyAccount: String, CaseIterable, Sendable {
    case openai = "openai-api-key"
    case elevenlabs = "elevenlabs-api-key"
    case speechmatics = "speechmatics-api-key"
    case assemblyai = "assemblyai-api-key"
    case anthropic = "anthropic-api-key"
}

public protocol SecretStore: Sendable {
    func secret(for account: KeyAccount) throws -> String?
    func setSecret(_ secret: String, for account: KeyAccount) throws
    func removeSecret(for account: KeyAccount) throws
}
