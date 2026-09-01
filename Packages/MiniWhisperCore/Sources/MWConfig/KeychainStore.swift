import Foundation
import MWSupport
import Security

/// Generic-password get/set/delete for the app's three accounts in the login keychain
/// (F3, §5.3), with a per-account cache so the press path never pays a keychain lookup
/// (§5.9). The cache is dropped on save and remove, so Settings edits take effect at once.
public final class KeychainStore: SecretStore, @unchecked Sendable {
    public static let service = "mini-whisper"

    private let api: any SecItemAPI
    private let lock = NSLock()
    private var cache: [KeyAccount: String?] = [:]

    public init(api: any SecItemAPI = SecItemBridge()) {
        self.api = api
    }

    public func secret(for account: KeyAccount) throws -> String? {
        // The lock is not held across the SecItem call: it can block on the system access
        // dialog, and a racing second reader only costs one redundant lookup.
        if let cached = lock.withLock({ cache[account] }) { return cached }
        let secret = try read(account)
        lock.withLock { cache[account] = .some(secret) }
        Log.config.debug("\(account.rawValue) \(secret == nil ? "absent" : "present") in Keychain")
        return secret
    }

    public func setSecret(_ secret: String, for account: KeyAccount) throws {
        let data = Data(secret.utf8)
        let query = item(account)
        let status = api.update(query, attributes: [kSecValueData as String: data])
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            var attributes = query
            attributes[kSecValueData as String] = data
            let added = api.add(attributes)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        default:
            throw KeychainError(status: status)
        }
        invalidate(account)
        Log.config.info("\(account.rawValue) saved to Keychain")
    }

    public func removeSecret(for account: KeyAccount) throws {
        let status = api.delete(item(account))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
        invalidate(account)
        Log.config.info("\(account.rawValue) removed from Keychain")
    }

    private func read(_ account: KeyAccount) throws -> String? {
        var query = item(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let result = api.copyMatching(query)
        switch result.status {
        case errSecSuccess:
            return result.data.map { String(decoding: $0, as: UTF8.self) }
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: result.status)
        }
    }

    /// The attributes that identify one item: no data-protection flag, so it lands in the
    /// login keychain the Python app used (§5.3).
    private func item(_ account: KeyAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    private func invalidate(_ account: KeyAccount) {
        lock.withLock { _ = cache.removeValue(forKey: account) }
    }
}
