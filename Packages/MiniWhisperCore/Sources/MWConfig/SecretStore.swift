/// The three generic-password accounts the app owns under service `mini-whisper`
/// (F3); names match `config.py:KEYRING_USERNAME` / `STREAMING_KEY_USERNAMES`.
public enum KeyAccount: String, CaseIterable, Sendable {
    case openai = "openai-api-key"
    case elevenlabs = "elevenlabs-api-key"
    case speechmatics = "speechmatics-api-key"
}

public protocol SecretStore: Sendable {
    func secret(for account: KeyAccount) throws -> String?
    func setSecret(_ secret: String, for account: KeyAccount) throws
    func removeSecret(for account: KeyAccount) throws
}
