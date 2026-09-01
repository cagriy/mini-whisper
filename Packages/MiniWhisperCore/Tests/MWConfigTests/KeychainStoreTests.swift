import Foundation
import Security
import Testing
@testable import MWConfig
import MWSupport
import MWTestSupport

/// Obviously fake — a real key must never appear in this repository.
private let fakeKey = "sk-test-not-a-real-key"

@Suite struct KeychainStoreTests {
    @Test func readQueryUsesServiceAccountAndLoginKeychain() throws {
        let api = FakeSecItemAPI()
        api.seed(fakeKey, account: "openai-api-key")
        let store = KeychainStore(api: api)

        #expect(try store.secret(for: .openai) == fakeKey)

        let query = try #require(api.copyMatchingCalls.first)
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "mini-whisper")
        #expect(query[kSecAttrAccount as String] as? String == "openai-api-key")
        #expect(query[kSecReturnData as String] as? Bool == true)
        // Exactly these keys: the login keychain is the default, and the flag that would
        // switch the item to the data-protection keychain is deliberately absent (§5.3).
        #expect(
            Set(query.keys) == [
                kSecClass as String,
                kSecAttrService as String,
                kSecAttrAccount as String,
                kSecReturnData as String,
                kSecMatchLimit as String,
            ]
        )
    }

    @Test func accountNamesMatchPython() {
        #expect(KeyAccount.openai.rawValue == "openai-api-key")
        #expect(KeyAccount.elevenlabs.rawValue == "elevenlabs-api-key")
        #expect(KeyAccount.speechmatics.rawValue == "speechmatics-api-key")
    }

    @Test func setUpdatesWhenPresentAddsWhenAbsent() throws {
        let api = FakeSecItemAPI()
        let store = KeychainStore(api: api)

        try store.setSecret(fakeKey, for: .elevenlabs)

        #expect(api.updateCalls.count == 1)
        #expect(api.addCalls.count == 1)
        #expect(api.storedSecret(account: "elevenlabs-api-key") == fakeKey)
        let attributes = try #require(api.addCalls.first)
        #expect(
            Set(attributes.keys) == [
                kSecClass as String,
                kSecAttrService as String,
                kSecAttrAccount as String,
                kSecValueData as String,
            ]
        )

        try store.setSecret("\(fakeKey)-rotated", for: .elevenlabs)

        #expect(api.updateCalls.count == 2)
        #expect(api.addCalls.count == 1)
        #expect(api.storedSecret(account: "elevenlabs-api-key") == "\(fakeKey)-rotated")
    }

    @Test func removeDeletesItem() throws {
        let api = FakeSecItemAPI()
        api.seed(fakeKey, account: "speechmatics-api-key")
        let store = KeychainStore(api: api)

        try store.removeSecret(for: .speechmatics)

        #expect(api.deleteCalls.count == 1)
        #expect(api.storedSecret(account: "speechmatics-api-key") == nil)
        #expect(try store.secret(for: .speechmatics) == nil)
    }

    @Test func cachesAfterFirstRead() throws {
        let api = FakeSecItemAPI()
        api.seed(fakeKey, account: "openai-api-key")
        let store = KeychainStore(api: api)

        #expect(try store.secret(for: .openai) == fakeKey)
        #expect(try store.secret(for: .openai) == fakeKey)
        #expect(api.copyMatchingCalls.count == 1)

        // A miss is cached too, so a key-less install pays one lookup per run.
        #expect(try store.secret(for: .elevenlabs) == nil)
        #expect(try store.secret(for: .elevenlabs) == nil)
        #expect(api.copyMatchingCalls.count == 2)
    }

    @Test func saveInvalidatesCache() throws {
        let api = FakeSecItemAPI()
        api.seed(fakeKey, account: "openai-api-key")
        let store = KeychainStore(api: api)
        #expect(try store.secret(for: .openai) == fakeKey)

        try store.setSecret("\(fakeKey)-rotated", for: .openai)

        #expect(try store.secret(for: .openai) == "\(fakeKey)-rotated")
        #expect(api.copyMatchingCalls.count == 2)
    }

    @Test func valueNeverAppearsInLogs() async throws {
        let api = FakeSecItemAPI()
        let store = KeychainStore(api: api)
        let sink = CapturingLogSink()

        try await Log.withSinks(debug: true, sinks: [sink]) {
            try store.setSecret(fakeKey, for: .openai)
            #expect(try store.secret(for: .openai) == fakeKey)
            try store.removeSecret(for: .openai)
        }

        #expect(!sink.lines.isEmpty)
        #expect(sink.lines.allSatisfy { !$0.contains(fakeKey) })
    }

    @Test func unexpectedStatusThrowsAndIsNotCached() throws {
        let api = FakeSecItemAPI()
        api.failure = errSecAuthFailed
        let store = KeychainStore(api: api)

        let thrown = #expect(throws: KeychainError.self) { try store.secret(for: .openai) }
        #expect(thrown?.status == errSecAuthFailed)
        #expect(thrown?.localizedDescription.isEmpty == false)
        #expect(throws: KeychainError.self) { try store.setSecret(fakeKey, for: .openai) }
        #expect(throws: KeychainError.self) { try store.removeSecret(for: .openai) }

        api.failure = nil
        api.seed(fakeKey, account: "openai-api-key")
        #expect(try store.secret(for: .openai) == fakeKey)
    }
}
