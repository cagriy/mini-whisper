import Testing

import MWCorrections

/// R7: whole-phrase, case-insensitive, whitespace-run tolerant, punctuation literal.
@Suite struct PhraseMatcherTests {
    private func matchCount(_ variant: String, in text: String) throws -> Int {
        try PhraseMatcher(variant: variant).matches(in: text).count
    }

    @Test func doesNotMatchInsideALongerWord() throws {
        #expect(try matchCount("chari", in: "a charity shop") == 0)
        #expect(try matchCount("mark", in: "open the bookmark") == 0)
        #expect(try matchCount("mark", in: "markdown") == 0)
    }

    @Test func apostropheIsABoundary() throws {
        let text = "eefa's laptop"
        let matcher = try PhraseMatcher(variant: "eefa")
        let range = try #require(matcher.matches(in: text).first)
        #expect(text[range] == "eefa")
    }

    @Test func whitespaceRunsBetweenWordsStillMatch() throws {
        #expect(try matchCount("get hub", in: "on get  hub today") == 1)
        #expect(try matchCount("get hub", in: "on get\nhub today") == 1)
        #expect(try matchCount("get hub", in: "on get \t hub today") == 1)
    }

    @Test func punctuationInsideThePhraseIsLiteral() throws {
        #expect(try matchCount("e-mail", in: "send an e-mail now") == 1)
        #expect(try matchCount("e-mail", in: "send an email now") == 0)
    }

    @Test func matchingIsCaseInsensitive() throws {
        #expect(try matchCount("get hub", in: "Get Hub and GET HUB") == 2)
    }

    @Test func digitsAndUnderscoresBlockTheMatch() throws {
        #expect(try matchCount("mark", in: "mark7") == 0)
        #expect(try matchCount("mark", in: "7mark") == 0)
        #expect(try matchCount("mark", in: "mark_two") == 0)
        #expect(try matchCount("mark", in: "two_mark") == 0)
    }

    @Test func anAdjacentCombiningMarkBlocksTheMatch() throws {
        #expect(try matchCount("eefa", in: "eefa\u{0301} today") == 0)
    }

    @Test func findsEveryOccurrence() throws {
        #expect(try matchCount("mark", in: "mark and mark, mark.") == 3)
    }

    @Test func anEmptyVariantThrows() {
        #expect(throws: PhraseMatcher.Failure.emptyVariant) {
            _ = try PhraseMatcher(variant: "   ")
        }
    }
}
