import MWConfig
import MWCorrections
import Testing

import MWProfiles

/// Vocabulary and correction injection (F28, R23, R24) and the effective-cleanup
/// conjunction (F26).
@Suite struct PromptComposerTests {
    private static let instructions = "Transcribe the audio."
    private static let cleanup = "Clean up the transcript."
    private static let slack = "com.tinyspeck.slackmacgap"

    private static let snapshot = CorrectionSnapshot(
        rules: [
            CorrectionRule(heard: "eefa", write: "Aoife", soundsLike: ["eva"], bundleID: slack),
            CorrectionRule(heard: "get hub", write: "GitHub"),
        ],
        vocabulary: ["xcodegen"]
    )

    @Test func nothingToInjectLeavesPromptsUnchanged() {
        #expect(
            PromptComposer.transcribePrompt(base: Self.instructions, terms: [])
                == Self.instructions
        )
        #expect(
            PromptComposer.cleanupPrompt(base: Self.cleanup, hints: .none, rules: [])
                == Self.cleanup
        )
    }

    @Test func termsAppendToTheTranscribePrompt() {
        #expect(
            PromptComposer.transcribePrompt(
                base: Self.instructions,
                terms: ["a", "b", "c"]
            ) == "Transcribe the audio.\n\nVocabulary (spell exactly as written): a, b, c"
        )
    }

    @Test func anEmptyInstructionsFileLeavesTheVocabularyLineAlone() {
        #expect(
            PromptComposer.transcribePrompt(base: "", terms: ["a"])
                == "Vocabulary (spell exactly as written): a"
        )
        #expect(PromptComposer.transcribePrompt(base: "", terms: []).isEmpty)
    }

    @Test func bothCorrectionBlocksAppendToTheCleanupPrompt() {
        #expect(
            PromptComposer.cleanupPrompt(
                base: Self.cleanup,
                hints: HintResolver.resolve(Self.snapshot, bundleID: Self.slack),
                rules: CorrectionResolver(rules: Self.snapshot.rules).rules(for: Self.slack)
            ) == """
                Clean up the transcript.

                Preserve these terms exactly as written: Aoife, GitHub, xcodegen

                Known corrections — replace the exact phrase on the left with the spelling on the right:
                "eefa" → "Aoife"
                "eva" → "Aoife"
                "get hub" → "GitHub"
                """
        )
    }

    @Test func vocabularyAloneStillReachesTheCleanupPrompt() {
        #expect(
            PromptComposer.cleanupPrompt(
                base: Self.cleanup,
                hints: HintResolver.resolve(
                    CorrectionSnapshot(rules: [], vocabulary: ["a", "b", "c"]), bundleID: nil
                ),
                rules: []
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
