import MWConfig
import Testing

import MWCorrections

/// R23 and R24: the exact text the batch prompt and the cleanup prompt carry.
@Suite struct PromptSectionsTests {
    private static let slack = "com.tinyspeck.slackmacgap"

    private static let snapshot = CorrectionSnapshot(
        rules: [
            CorrectionRule(
                heard: "eefa", write: "Aoife", soundsLike: ["eefa", "eva"], bundleID: slack
            ),
            CorrectionRule(heard: "get hub", write: "GitHub"),
        ],
        vocabulary: ["xcodegen", "Mini Whisper"]
    )

    private static func blocks(_ snapshot: CorrectionSnapshot) -> [String] {
        PromptSections.cleanupBlocks(
            hints: HintResolver.resolve(snapshot, bundleID: slack),
            rules: CorrectionResolver(rules: snapshot.rules).rules(for: slack)
        )
    }

    @Test func theVocabularyLineListsEveryTerm() {
        #expect(
            PromptSections.vocabularyLine(terms: ["a", "b", "c"])
                == "Vocabulary (spell exactly as written): a, b, c"
        )
    }

    @Test func theVocabularyLineIsAbsentWithoutTerms() {
        #expect(PromptSections.vocabularyLine(terms: []) == nil)
    }

    @Test func bothCleanupBlocksAreEmittedInOrder() {
        #expect(
            Self.blocks(Self.snapshot) == [
                "\n\nPreserve these terms exactly as written: Aoife, GitHub, xcodegen, Mini Whisper",
                """
                \n
                Known corrections — replace the exact phrase on the left with the spelling on the right:
                "eefa" → "Aoife"
                "eva" → "Aoife"
                "get hub" → "GitHub"
                """,
            ]
        )
    }

    @Test func theCorrectionsBlockIsOmittedWithoutRules() {
        #expect(
            Self.blocks(CorrectionSnapshot(rules: [], vocabulary: ["xcodegen"])) == [
                "\n\nPreserve these terms exactly as written: xcodegen"
            ]
        )
    }

    @Test func thePreserveBlockIsOmittedWithoutTerms() {
        let rules = CorrectionResolver(rules: [CorrectionRule(heard: "get hub", write: "GitHub")])
            .rules(for: nil)

        #expect(
            PromptSections.cleanupBlocks(hints: .none, rules: rules) == [
                """
                \n
                Known corrections — replace the exact phrase on the left with the spelling on the right:
                "get hub" → "GitHub"
                """
            ]
        )
    }

    @Test func anEmptySnapshotYieldsNoBlocks() {
        #expect(Self.blocks(CorrectionSnapshot(rules: [], vocabulary: [])).isEmpty)
    }
}
