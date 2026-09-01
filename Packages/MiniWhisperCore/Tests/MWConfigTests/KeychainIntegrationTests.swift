import Foundation
import Security
import Testing
@testable import MWConfig

/// Opt-in: writes to the user's real login keychain and can raise the system access
/// dialog, so it never runs in a plain `swift test`.
/// Command: `MW_INTEGRATION=1 swift test --filter KeychainIntegrationTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1"))
struct KeychainIntegrationTests {
    @Test func roundTripThroughLoginKeychain() throws {
        let api = SecItemBridge()
        let secret = Data("sk-test-not-a-real-key".utf8)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainStore.service,
            kSecAttrAccount as String: "integration-test-key",
        ]
        var readQuery = item
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        _ = api.delete(item)
        defer { _ = api.delete(item) }

        var attributes = item
        attributes[kSecValueData as String] = secret
        #expect(api.add(attributes) == errSecSuccess)

        let read = api.copyMatching(readQuery)
        #expect(read.status == errSecSuccess)
        #expect(read.data == secret)

        #expect(api.delete(item) == errSecSuccess)
        #expect(api.copyMatching(readQuery).status == errSecItemNotFound)
    }
}
