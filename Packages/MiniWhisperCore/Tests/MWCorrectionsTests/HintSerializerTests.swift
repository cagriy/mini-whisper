import MWConfig
import Testing

import MWCorrections

/// R18–R21: the per-engine caps, filters and skip reasons.
@Suite struct HintSerializerTests {
    private static let slack = "com.tinyspeck.slackmacgap"

    @Test func contextualStringsSendTheFirstHundredAndReportTheRest() {
        let rules =
            [
                CorrectionRule(
                    heard: "eefa", write: "Aoife", soundsLike: ["eva"], bundleID: Self.slack
                )
            ]
            + (0..<39).map {
                CorrectionRule(heard: "heard\($0)", write: "Write\($0)", soundsLike: ["alias\($0)"])
            }
        let hints = HintResolver.resolve(
            CorrectionSnapshot(rules: rules, vocabulary: []), bundleID: Self.slack
        )
        #expect(hints.terms.count == 120)

        let capped = HintSerializer.contextualStrings(hints)

        #expect(capped.sent.count == 100)
        #expect(capped.skipped.count == 20)
        #expect(capped.skipped.allSatisfy { $0.reason == .overCap })
        // The app-scoped rule resolves first, so its terms are never the ones dropped.
        #expect(capped.sent.prefix(3) == ["Aoife", "eefa", "eva"])
        #expect(capped.skipped.map(\.term) == Array(hints.terms.suffix(20)))
    }

    @Test func openAIKeywordsStripTheFourForbiddenCharacters() {
        let hints = RecognitionHints(
            terms: ["a<b", "c>d", "e\r\nf", "<>", "plain"], rules: [], vocabulary: []
        )

        let capped = HintSerializer.openAIKeywords(hints)

        #expect(capped.sent == ["ab", "cd", "ef", "plain"])
        #expect(capped.skipped == [SkippedHint(term: "<>", reason: .emptyAfterFilter)])
    }

    @Test func speechmaticsEntriesAreRulesThenVocabularyInResolverOrder() {
        let hints = RecognitionHints(
            terms: [],
            rules: [
                RecognitionHints.HintRule(write: "Aoife", soundsLike: ["eefa", "eva"]),
                RecognitionHints.HintRule(write: "GitHub", soundsLike: ["get hub"]),
            ],
            vocabulary: ["xcodegen"]
        )

        let capped = HintSerializer.speechmaticsVocab(hints)

        #expect(
            capped.sent == [
                HintSerializer.VocabEntry(content: "Aoife", soundsLike: ["eefa", "eva"]),
                HintSerializer.VocabEntry(content: "GitHub", soundsLike: ["get hub"]),
                HintSerializer.VocabEntry(content: "xcodegen", soundsLike: []),
            ]
        )
        #expect(capped.skipped.isEmpty)
    }

    @Test func speechmaticsSkipsContentOverSixWordsOrWithATooLongWord() {
        let long = String(repeating: "x", count: 4_001)
        let hints = RecognitionHints(
            terms: [],
            rules: [
                RecognitionHints.HintRule(write: "one two three four five six seven", soundsLike: []),
                RecognitionHints.HintRule(write: long, soundsLike: []),
                RecognitionHints.HintRule(write: "Aoife", soundsLike: []),
            ],
            vocabulary: []
        )

        let capped = HintSerializer.speechmaticsVocab(hints)

        #expect(capped.sent.map(\.content) == ["Aoife"])
        #expect(
            capped.skipped == [
                SkippedHint(term: "one two three four five six seven", reason: .tooManyWords),
                SkippedHint(term: long, reason: .wordTooLong),
            ]
        )
    }

    @Test func aSkippableSoundsLikeIsDroppedButItsEntrySurvives() {
        let hints = RecognitionHints(
            terms: [],
            rules: [
                RecognitionHints.HintRule(
                    write: "Aoife", soundsLike: ["one two three four five six seven", "eva"]
                )
            ],
            vocabulary: []
        )

        let capped = HintSerializer.speechmaticsVocab(hints)

        #expect(capped.sent == [HintSerializer.VocabEntry(content: "Aoife", soundsLike: ["eva"])])
        #expect(
            capped.skipped == [
                SkippedHint(term: "one two three four five six seven", reason: .tooManyWords)
            ]
        )
    }

    @Test func speechmaticsCapsAtAThousandEntries() {
        let hints = RecognitionHints(
            terms: [], rules: [], vocabulary: (0..<1_200).map { "term\($0)" }
        )

        let capped = HintSerializer.speechmaticsVocab(hints)

        #expect(capped.sent.count == 1_000)
        #expect(capped.skipped.count == 200)
        #expect(capped.skipped.allSatisfy { $0.reason == .overCap })
        #expect(capped.skipped.first?.term == "term1000")
    }
}
