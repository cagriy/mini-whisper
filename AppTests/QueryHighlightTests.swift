import Testing
@testable import MiniWhisper

/// The results page marks every occurrence of the query, as search matched it (design §5.9).
@Suite struct QueryHighlightTests {
    private static func marked(_ query: String, in text: String) -> [String] {
        QueryHighlight.matches(of: query, in: text).map { String(text[$0]) }
    }

    @Test func marksEveryOccurrenceIgnoringCase() {
        #expect(Self.marked("catalog", in: "Catalog entries: the catalog and CATALOGS") == ["Catalog", "catalog", "CATALOG"])
    }

    @Test func surroundingWhitespaceIsNotPartOfTheQuery() {
        #expect(Self.marked("  catalog\n", in: "the catalog notes") == ["catalog"])
    }

    @Test func anEmptyQueryMarksNothing() {
        #expect(Self.marked(" ", in: "the catalog notes").isEmpty)
    }

    @Test func occurrencesDoNotOverlap() {
        #expect(Self.marked("aa", in: "aaaa a") == ["aa", "aa"])
    }

    @Test func theAttributedTextKeepsTheWholeText() {
        let text = "Thanks Orla, the catalog notes look good."

        #expect(String(QueryHighlight.attributed(text, query: "catalog").characters) == text)
    }
}
