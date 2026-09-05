import MWConfig
import Testing

import MWCorrections

/// R17: what each engine is offered, in which order, once each.
@Suite struct HintResolverTests {
    private static let slack = "com.tinyspeck.slackmacgap"

    private static let appRule = CorrectionRule(
        id: "app", heard: "eefa", write: "Aoife", soundsLike: ["eefa", "eva"], bundleID: slack
    )
    private static let globalRule = CorrectionRule(
        id: "global", heard: "get hub", write: "GitHub", soundsLike: ["get hub", "git hub"]
    )

    private static let snapshot = CorrectionSnapshot(
        rules: [globalRule, appRule], vocabulary: ["xcodegen", "Mini Whisper"]
    )

    @Test func termsAreAppRulesThenGlobalRulesThenVocabulary() {
        let hints = HintResolver.resolve(Self.snapshot, bundleID: Self.slack)

        #expect(
            hints.terms == [
                "Aoife", "eefa", "eva", "GitHub", "get hub", "git hub", "xcodegen", "Mini Whisper",
            ]
        )
    }

    @Test func duplicatesByNormalisedKeyKeepTheFirstSpelling() {
        let snapshot = CorrectionSnapshot(
            rules: [Self.appRule], vocabulary: ["EVA", "  Aoife ", "xcodegen"]
        )

        let hints = HintResolver.resolve(snapshot, bundleID: Self.slack)

        #expect(hints.terms == ["Aoife", "eefa", "eva", "xcodegen"])
        #expect(hints.vocabulary == ["EVA", "Aoife", "xcodegen"])
    }

    @Test func disabledRulesAndOtherAppsContributeNothing() {
        var disabled = Self.globalRule
        disabled.enabled = false
        let snapshot = CorrectionSnapshot(rules: [disabled, Self.appRule], vocabulary: [])

        let hints = HintResolver.resolve(snapshot, bundleID: "com.apple.Terminal")

        #expect(hints == .none)
    }

    @Test func hintRulesCarryTheWriteAndItsVariantsWithTheWriteExcluded() {
        let rule = CorrectionRule(
            heard: "github", write: "GitHub", soundsLike: ["GITHUB", "get hub"]
        )

        let hints = HintResolver.resolve(
            CorrectionSnapshot(rules: [Self.appRule, rule], vocabulary: []), bundleID: Self.slack
        )

        #expect(hints.rules.map(\.write) == ["Aoife", "GitHub"])
        #expect(hints.rules.map(\.soundsLike) == [["eefa", "eva"], ["get hub"]])
    }

    @Test func vocabularyKeepsStoredOrder() {
        let snapshot = CorrectionSnapshot(rules: [], vocabulary: ["  b ", "a", "c"])

        #expect(HintResolver.resolve(snapshot, bundleID: nil).vocabulary == ["b", "a", "c"])
    }

    @Test func anEmptySnapshotResolvesToNone() {
        #expect(HintResolver.resolve(CorrectionSnapshot(rules: [], vocabulary: []), bundleID: nil) == .none)
        #expect(RecognitionHints.none.terms.isEmpty)
    }

    @Test func aSnapshotIsTakenFromTheConfig() {
        var config = Config()
        config.corrections = [Self.globalRule]
        config.vocabulary = ["xcodegen"]

        let snapshot = CorrectionSnapshot(config: config)

        #expect(snapshot.rules == [Self.globalRule])
        #expect(snapshot.vocabulary == ["xcodegen"])
    }
}
