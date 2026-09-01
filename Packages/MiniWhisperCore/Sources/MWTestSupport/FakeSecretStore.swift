import Foundation
import MWConfig

/// Dictionary-backed `SecretStore` for the modules that only need to know whether a key
/// is present (engine selection, the pipeline's no-key rule).
public final class FakeSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [KeyAccount: String]

    public init(_ secrets: [KeyAccount: String] = [:]) {
        self.secrets = secrets
    }

    public func secret(for account: KeyAccount) throws -> String? {
        lock.withLock { secrets[account] }
    }

    public func setSecret(_ secret: String, for account: KeyAccount) throws {
        lock.withLock { secrets[account] = secret }
    }

    public func removeSecret(for account: KeyAccount) throws {
        lock.withLock { secrets[account] = nil }
    }
}
