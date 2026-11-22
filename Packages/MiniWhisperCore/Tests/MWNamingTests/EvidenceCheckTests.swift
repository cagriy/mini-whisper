import Foundation
import MWMeetings
import MWTranscription
import Testing

import MWNaming

@Suite struct EvidenceCheckTests {
    private func segment(_ speaker: Int, _ start: Double, _ text: String) -> Segment {
        Segment(speaker: speaker, start: start, end: start + 2, text: text, session: 1)
    }

    private func raw(_ name: String, turn: Int = 1, quote: String) -> RawSuggestion {
        RawSuggestion(speaker: "S1", name: name, confidence: "certain", kind: "self_introduction", turn: turn, quote: quote)
    }

    private func verify(_ text: String, name: String = "Kate Morgan", quote: String) -> NameEvidence? {
        let rendered = NamingTranscript.render(segments: [segment(1, 4, text)])
        return EvidenceCheck.verify(raw(name, quote: quote), in: rendered)
    }

    @Test func exactQuoteIsTheTranscriptsOwnText() throws {
        let said = segment(1, 4, "Hi, I'm Kate Morgan from sales.")
        let rendered = NamingTranscript.render(segments: [said])

        let evidence = try #require(EvidenceCheck.verify(raw("Kate Morgan", quote: "I'm Kate Morgan"), in: rendered))

        #expect(evidence == NameEvidence(segment: said.id, time: 4, text: "I'm Kate Morgan"))
    }

    @Test(arguments: [
        // Curly apostrophe in the quote, straight in the transcript, and the reverse.
        ("Hi, I'm Kate Morgan from sales.", "I’m Kate Morgan", "I'm Kate Morgan"),
        ("Hi, I‘m Kate Morgan from sales.", "I'm Kate Morgan", "I‘m Kate Morgan"),
        ("Hi, I‛m Kate Morgan from sales.", "I‚m Kate Morgan", "I‛m Kate Morgan"),
        ("They call me “Kate Morgan” here.", #"call me "Kate Morgan""#, "call me “Kate Morgan”"),
        ("They call me „Kate Morgan” here.", "call me “Kate Morgan”", "call me „Kate Morgan”"),
        // Whitespace collapses on both sides; the quote's ends are trimmed.
        ("Hi, I'm Kate Morgan from sales.", "  I'm   Kate\nMorgan ", "I'm Kate Morgan"),
        ("Hi, I'm  Kate\tMorgan from sales.", "I'm Kate Morgan", "I'm  Kate\tMorgan"),
        // Case and diacritics fold.
        ("Hi, I'm Kate Morgan from sales.", "i'M KATE morgan", "I'm Kate Morgan"),
        ("Hi, I'm Káte Morgan from sales.", "I'm Kate Morgán", "I'm Káte Morgan"),
    ])
    func normalisedVariantsPass(_ text: String, _ quote: String, _ stored: String) throws {
        let evidence = try #require(verify(text, quote: quote))
        #expect(evidence.text == stored)
    }

    @Test func nameIsNormalisedLikeTheQuote() {
        #expect(verify("This is Siobhán O’Brien.", name: "siobhan o'brien", quote: "This is Siobhan O'Brien") != nil)
    }

    @Test func quoteFromAnotherTurnFails() {
        let rendered = NamingTranscript.render(segments: [
            segment(1, 0, "Morning all."),
            segment(2, 5, "Hi, I'm Kate Morgan."),
        ])

        #expect(EvidenceCheck.verify(raw("Kate Morgan", turn: 1, quote: "I'm Kate Morgan"), in: rendered) == nil)
        #expect(EvidenceCheck.verify(raw("Kate Morgan", turn: 2, quote: "I'm Kate Morgan"), in: rendered) != nil)
        #expect(EvidenceCheck.verify(raw("Kate Morgan", turn: 3, quote: "I'm Kate Morgan"), in: rendered) == nil)
    }

    @Test func quoteWithoutTheNameFails() {
        #expect(verify("Hi, I'm Kate Morgan from sales.", quote: "from sales") == nil)
        #expect(verify("Hi, I'm Kate Morgan from sales.", quote: "I'm Kate") == nil)
    }

    @Test func paraphraseFails() {
        #expect(verify("Hi, I'm Kate Morgan from sales.", quote: "My name is Kate Morgan") == nil)
        #expect(verify("Hi, I'm Kate Morgan from sales.", quote: "I am Kate Morgan") == nil)
    }

    @Test func emptyQuoteFails() {
        #expect(verify("Hi, I'm Kate Morgan from sales.", quote: "  ") == nil)
    }

    @Test func evidenceNamesTheSegmentHoldingTheMatchStart() throws {
        let hello = segment(1, 10, "Hello everyone.")
        let intro = segment(1, 13, "So I'm Kate Morgan and")
        let role = segment(1, 16, "I run the sales team.")
        let rendered = NamingTranscript.render(segments: [hello, intro, role])

        let spanning = try #require(EvidenceCheck.verify(
            raw("Kate Morgan", quote: "I'm Kate Morgan and I run"), in: rendered
        ))
        #expect(spanning == NameEvidence(segment: intro.id, time: 13, text: "I'm Kate Morgan and I run"))

        let fromStart = try #require(EvidenceCheck.verify(
            raw("Kate Morgan", quote: "everyone. So I'm Kate Morgan"), in: rendered
        ))
        #expect(fromStart == NameEvidence(segment: hello.id, time: 10, text: "everyone. So I'm Kate Morgan"))

        let last = try #require(EvidenceCheck.verify(raw("Kate", quote: "Kate Morgan and I run the sales"), in: rendered))
        #expect(last.segment == intro.id)
    }

    @Test func longEvidenceIsCutTo300CharactersAtAWordBoundary() throws {
        let filler = Array(repeating: "lorem", count: 80).joined(separator: " ")
        let quote = "I'm Kate Morgan and " + filler
        let rendered = NamingTranscript.render(segments: [segment(1, 0, "Hi. " + quote + " Thanks.")])

        let evidence = try #require(EvidenceCheck.verify(raw("Kate Morgan", quote: quote), in: rendered))

        #expect(quote.count > 300)
        #expect(evidence.text.count <= 300)
        #expect(evidence.text.count > 290)
        #expect(quote.hasPrefix(evidence.text))
        #expect(evidence.text.hasSuffix("lorem"))
    }

    @Test func cutDropsAWordThatCrossesTheLimit() throws {
        let quote = "Kate " + String(repeating: "a", count: 310)
        let rendered = NamingTranscript.render(segments: [segment(1, 0, quote)])

        let evidence = try #require(EvidenceCheck.verify(raw("Kate", quote: quote), in: rendered))

        #expect(evidence.text == "Kate")
    }

    @Test func aWordLongerThanTheLimitIsCutAtTheLimit() throws {
        let quote = String(repeating: "a", count: 310)
        let rendered = NamingTranscript.render(segments: [segment(1, 0, quote)])

        let evidence = try #require(EvidenceCheck.verify(raw("aaa", quote: quote), in: rendered))

        #expect(evidence.text == String(repeating: "a", count: 300))
    }
}
