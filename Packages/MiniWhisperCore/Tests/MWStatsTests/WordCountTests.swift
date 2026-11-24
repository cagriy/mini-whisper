import Testing

import MWStats

@Suite struct WordCountTests {
    @Test func punctuationIsNotAWordAndAContractionIsOne() {
        #expect(WordCount.count("Hello, world. It's fine.") == 4)
    }

    @Test func anUnspacedJapaneseSentenceCountsItsWords() {
        #expect(WordCount.count("今日は良い天気です") > 1)
    }

    // Word breaking next to CJK reports the spaces between runs as words of their own.
    @Test func aMixedLatinAndJapaneseLineCountsNoSpaces() {
        #expect(WordCount.count("Meeting は 明日 です") == 4)
    }

    @Test func emptyTextCountsZero() {
        #expect(WordCount.count("") == 0)
        #expect(WordCount.count("  \n ") == 0)
    }
}
