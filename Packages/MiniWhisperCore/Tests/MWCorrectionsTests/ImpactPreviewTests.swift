import MWConfig
import Testing

import MWCorrections

/// R31: how many stored dictations a draft rule would have changed.
@Suite struct ImpactPreviewTests {
    private static let slack = "com.tinyspeck.slackmacgap"

    private static let appRule = CorrectionRule(
        heard: "eefa", write: "Aoife", soundsLike: ["eva"], bundleID: slack
    )

    @Test func entriesOutsideTheRulesScopeAreExcluded() {
        let result = ImpactPreview.compute(
            rule: Self.appRule,
            over: [
                ImpactPreview.Entry(text: "eefa is here", bundleID: Self.slack),
                ImpactPreview.Entry(text: "eefa is here", bundleID: "com.apple.Terminal"),
                ImpactPreview.Entry(text: "nothing here", bundleID: Self.slack),
            ]
        )

        #expect(result.matching == 1)
        #expect(result.total == 2)
        #expect(result.historyOff == false)
    }

    @Test func aGlobalRuleCountsEveryEntry() {
        let result = ImpactPreview.compute(
            rule: CorrectionRule(heard: "get hub", write: "GitHub"),
            over: [
                ImpactPreview.Entry(text: "get hub actions", bundleID: Self.slack),
                ImpactPreview.Entry(text: "GET HUB again", bundleID: nil),
                ImpactPreview.Entry(text: "unrelated", bundleID: nil),
            ]
        )

        #expect(result.matching == 2)
        #expect(result.total == 3)
    }

    @Test func aSoundsLikeVariantCounts() {
        let result = ImpactPreview.compute(
            rule: Self.appRule,
            over: [ImpactPreview.Entry(text: "ask eva about it", bundleID: Self.slack)]
        )

        #expect(result.matching == 1)
        #expect(result.snippets == ["ask eva about it"])
    }

    @Test func aShortEntryIsItsOwnSnippet() {
        let result = ImpactPreview.compute(
            rule: Self.appRule,
            over: [ImpactPreview.Entry(text: "eefa is here", bundleID: Self.slack)]
        )

        #expect(result.snippets == ["eefa is here"])
    }

    @Test func aLongEntryIsTruncatedAroundTheFirstMatch() {
        let filler = String(repeating: "ab", count: 20)
        let text = filler + " eefa " + filler

        let result = ImpactPreview.compute(
            rule: Self.appRule, over: [ImpactPreview.Entry(text: text, bundleID: Self.slack)]
        )

        // 30 characters either side of the match at 41..<45.
        #expect(result.snippets == ["…" + String(text.dropFirst(11).prefix(64)) + "…"])
    }

    @Test func atMostThreeSnippetsAreReturned() {
        let entries = (0..<4).map {
            ImpactPreview.Entry(text: "entry \($0) mentions eefa", bundleID: Self.slack)
        }

        let result = ImpactPreview.compute(rule: Self.appRule, over: entries)

        #expect(result.matching == 4)
        #expect(result.snippets.count == 3)
        #expect(result.snippets.first == "entry 0 mentions eefa")
    }

    @Test func aNilEntryListReadsAsHistoryOff() {
        let result = ImpactPreview.compute(rule: Self.appRule, over: nil)

        #expect(result.historyOff)
        #expect(result.matching == 0)
        #expect(result.total == 0)
        #expect(result.snippets.isEmpty)
    }
}
