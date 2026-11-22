import Testing
import MWSupport

@Suite struct TokenUsageTests {
    @Test func cacheFieldsDefaultToZero() {
        let usage = TokenUsage(inputTokens: 1, outputTokens: 2)

        #expect(usage.cacheReadTokens == 0)
        #expect(usage.cacheWriteTokens == 0)
    }

    @Test func cacheFieldsAreSettable() {
        var usage = TokenUsage(inputTokens: 1, outputTokens: 2, cacheReadTokens: 3, cacheWriteTokens: 4)
        #expect(usage.cacheReadTokens == 3)
        #expect(usage.cacheWriteTokens == 4)

        usage.cacheReadTokens = 5
        usage.cacheWriteTokens = 6

        #expect(usage == TokenUsage(inputTokens: 1, outputTokens: 2, cacheReadTokens: 5, cacheWriteTokens: 6))
    }
}
