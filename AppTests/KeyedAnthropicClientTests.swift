import Foundation
import MWTranscription
import Testing
@testable import MiniWhisper

@Suite struct KeyedAnthropicClientTests {
    private static let request = NamingRequest(system: "", blocks: [], cacheBlocks: 0, state: "", schema: Data())

    @Test(arguments: [nil, ""] as [String?])
    func suggestNamesWithoutAKeyThrowsMissingAPIKey(_ key: String?) async {
        let secrets = FakeSecrets()
        secrets.stored[.anthropic] = key

        await #expect(throws: MissingAPIKey.self) {
            try await KeyedAnthropicClient(secrets: secrets).suggestNames(Self.request)
        }
    }
}
