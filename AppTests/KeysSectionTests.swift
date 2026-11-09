import MWConfig
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct KeysSectionTests {
    /// R6: every Keychain account, the two meeting providers included, has a row.
    @Test func everyKeyAccountHasARow() {
        #expect(KeysSection.rows.map(\.0) == KeyAccount.allCases)
        #expect(KeysSection.rows.map(\.1) == ["OpenAI", "ElevenLabs", "Speechmatics", "AssemblyAI", "Anthropic"])
    }
}
