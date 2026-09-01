import Foundation
import MWConfig
import Security

/// In-memory keychain keyed by account, recording every call so tests can assert on the
/// query attributes the store builds.
public final class FakeSecItemAPI: SecItemAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var recordedCopyMatching: [[String: Any]] = []
    private var recordedAdds: [[String: Any]] = []
    private var recordedUpdates: [(query: [String: Any], attributes: [String: Any])] = []
    private var recordedDeletes: [[String: Any]] = []

    /// When set, every call fails with this status instead of touching `items`.
    public var failure: OSStatus? {
        get { lock.withLock { failureStatus } }
        set { lock.withLock { failureStatus = newValue } }
    }
    private var failureStatus: OSStatus?

    public init() {}

    public func seed(_ secret: String, account: String) {
        lock.withLock { items[account] = Data(secret.utf8) }
    }

    public func storedSecret(account: String) -> String? {
        lock.withLock { items[account] }.map { String(decoding: $0, as: UTF8.self) }
    }

    public var copyMatchingCalls: [[String: Any]] { lock.withLock { recordedCopyMatching } }
    public var addCalls: [[String: Any]] { lock.withLock { recordedAdds } }
    public var updateCalls: [(query: [String: Any], attributes: [String: Any])] {
        lock.withLock { recordedUpdates }
    }
    public var deleteCalls: [[String: Any]] { lock.withLock { recordedDeletes } }

    public func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            recordedCopyMatching.append(query)
            if let failureStatus { return (failureStatus, nil) }
            guard let data = items[Self.account(query)] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    public func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            recordedAdds.append(attributes)
            if let failureStatus { return failureStatus }
            let account = Self.account(attributes)
            guard items[account] == nil else { return errSecDuplicateItem }
            items[account] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    public func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            recordedUpdates.append((query, attributes))
            if let failureStatus { return failureStatus }
            let account = Self.account(query)
            guard items[account] != nil else { return errSecItemNotFound }
            items[account] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            recordedDeletes.append(query)
            if let failureStatus { return failureStatus }
            return items.removeValue(forKey: Self.account(query)) == nil
                ? errSecItemNotFound : errSecSuccess
        }
    }

    private static func account(_ query: [String: Any]) -> String {
        query[kSecAttrAccount as String] as? String ?? ""
    }
}
