import MWConfig
import Testing

import MWProfiles

/// Vocabulary injection (F28) and the effective-cleanup conjunction (F26).
@Suite struct PromptComposerTests {
    private static let instructions = "Transcribe the audio."
    private static let cleanup = "Clean up the transcript."

    @Test func emptyVocabularyLeavesPromptsUnchanged() {
        #expect(
            PromptComposer.transcribeInstructions(base: Self.instructions, vocabulary: [])
                == Self.instructions
        )
        #expect(
            PromptComposer.cleanupPrompt(base: Self.cleanup, vocabulary: [])
                == Self.cleanup
        )
    }

    @Test func vocabularyAppendsToTranscribeInstructions() {
        #expect(
            PromptComposer.transcribeInstructions(
                base: Self.instructions,
                vocabulary: ["a", "b", "c"]
            ) == "Transcribe the audio.\n\nVocabulary (spell exactly as written): a, b, c"
        )
    }

    @Test func vocabularyAppendsToCleanupPrompt() {
        #expect(
            PromptComposer.cleanupPrompt(
                base: Self.cleanup,
                vocabulary: ["a", "b", "c"]
            ) == "Clean up the transcript.\n\nPreserve these terms exactly as written: a, b, c"
        )
    }

    @Test(arguments: [
        (true, true, true, true),
        (false, true, true, false),
        (true, false, true, false),
        (true, true, false, false),
        (false, false, true, false),
        (false, true, false, false),
        (true, false, false, false),
        (false, false, false, false),
    ])
    func effectiveCleanupRequiresAllThree(
        global: Bool,
        hasOpenAIKey: Bool,
        profile: Bool,
        expected: Bool
    ) {
        var config = Config()
        config.cleanupEnabled = global
        let resolved = ResolvedProfile(
            name: "Terminal",
            cleanupEnabled: profile,
            submitKey: .enter,
            cleanupPrompt: Self.cleanup,
            isDefault: false
        )
        #expect(
            EffectiveCleanup.isOn(config: config, hasOpenAIKey: hasOpenAIKey, profile: resolved)
                == expected
        )
    }
}
