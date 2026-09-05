import Foundation
import MWConfig
import Testing

import MWCorrections

/// R8/R9: one pass over the original text, longest then app then stored order.
@Suite struct CorrectionApplierTests {
    private func resolved(
        _ heard: String,
        _ write: String,
        variants: [String]? = nil,
        appScoped: Bool = false
    ) -> ResolvedRule {
        ResolvedRule(
            rule: CorrectionRule(
                heard: heard, write: write, bundleID: appScoped ? "com.tinyspeck.slackmacgap" : nil
            ),
            variants: variants ?? [heard],
            isAppScoped: appScoped
        )
    }

    private func apply(_ rules: [ResolvedRule], to text: String) -> CorrectionApplier.Application {
        CorrectionApplier(rules: rules).apply(to: text)
    }

    @Test func replacesOneOccurrence() {
        let result = apply([resolved("get hub", "GitHub")], to: "push it to get hub tonight")

        #expect(result.text == "push it to GitHub tonight")
        #expect(result.replacements == 1)
    }

    @Test func replacesEveryOccurrenceAcrossSeveralRules() {
        let result = apply(
            [resolved("get hub", "GitHub"), resolved("eefa", "Aoife")],
            to: "eefa pushed to get hub, then eefa opened get hub again"
        )

        #expect(result.text == "Aoife pushed to GitHub, then Aoife opened GitHub again")
        #expect(result.replacements == 4)
    }

    @Test func theWriteIsSplicedVerbatim() {
        let result = apply([resolved("e mail", "e‑mail (private)")], to: "send an e mail now")

        #expect(result.text == "send an e‑mail (private) now")
    }

    @Test func aSoundsLikeVariantFiresTheSameReplacement() {
        let rule = resolved("eefa", "Aoife", variants: ["eefa", "eva"])

        #expect(apply([rule], to: "ask eva about it").text == "ask Aoife about it")
        #expect(apply([rule], to: "ask eefa about it").text == "ask Aoife about it")
    }

    @Test func theLongestOverlappingMatchWins() {
        let result = apply(
            [resolved("get hub", "GitHub"), resolved("get hub actions", "GitHub Actions")],
            to: "run get hub actions now"
        )

        #expect(result.text == "run GitHub Actions now")
        #expect(result.replacements == 1)
    }

    @Test func anAppRuleBeatsAGlobalRuleOfTheSameLength() {
        let result = apply(
            [resolved("eefa", "Eva"), resolved("eefa", "Aoife", appScoped: true)],
            to: "ask eefa"
        )

        #expect(result.text == "ask Aoife")
    }

    @Test func equalLengthAndScopeFallsBackToStoredOrder() {
        let result = apply(
            [resolved("eefa", "Aoife"), resolved("eefa", "Eva")],
            to: "ask eefa"
        )

        #expect(result.text == "ask Aoife")
    }

    @Test func replacedTextIsNeverRescanned() {
        let result = apply(
            [resolved("get hub", "octocat"), resolved("octocat", "GitHub")],
            to: "get hub and octocat"
        )

        #expect(result.text == "octocat and GitHub")
        #expect(result.replacements == 2)
    }

    @Test func aCaseOnlyFixApplies() {
        #expect(apply([resolved("github", "GitHub")], to: "on github").text == "on GitHub")
    }

    @Test func noRulesIsTheIdentity() {
        let result = apply([], to: "nothing to do here")

        #expect(result.text == "nothing to do here")
        #expect(result.replacements == 0)
        #expect(result.droppedVariants == 0)
    }

    @Test func aVariantThatCannotCompileIsDroppedAndCounted() {
        let rule = ResolvedRule(
            rule: CorrectionRule(heard: "eefa", write: "Aoife"),
            variants: ["", "eefa"],
            isAppScoped: false
        )

        let result = apply([rule], to: "ask eefa")
        #expect(result.text == "ask Aoife")
        #expect(result.droppedVariants == 1)
    }

    /// N3, and the regression it guards: compiling a variant's pattern per match
    /// rather than once per applier.
    @Test func hundredsOfRulesStayUnderAMillisecond() {
        let rules = (0..<300).map { resolved("term\($0) phrase", "Term\($0)") }
        let text = String(repeating: "a dictation sized sentence about term7 phrase. ", count: 26)
        #expect(text.count > 1_200)
        let applier = CorrectionApplier(rules: rules)

        let elapsed = ContinuousClock().measure { _ = applier.apply(to: text) }

        #expect(elapsed < .milliseconds(100))
    }
}
