import Foundation
import MWTestSupport
import Testing

import MWMeetings

@Suite struct MeetingSearchTests {
    private let search = MeetingSearch()
    private let created = Date(timeIntervalSince1970: 1_794_222_000)

    private func segment(_ start: Double, _ text: String) -> Segment {
        Segment(speaker: 0, start: start, end: start + 2, text: text, session: 1)
    }

    private func summary(_ text: String) -> Summary {
        Summary(text: text, model: "claude-sonnet-5-5", createdAt: created, inputTokens: 1, outputTokens: 1, costUSD: 0)
    }

    @Test func matchesCaseInsensitivelyAcrossTitleTranscriptNotesSummary() {
        let byTitle = MeetingFixtures.make(title: "Budget REVIEW")
        let bySegment = MeetingFixtures.make(segments: [segment(5, "The review is on Friday.")])
        let byNote = MeetingFixtures.make(notes: [Note(time: 7, text: "Prep Review deck", createdAt: created)])
        let bySummary = MeetingFixtures.make(summary: summary("## Summary\n\nA short reVIEW of the plan."))
        let none = MeetingFixtures.make(segments: [segment(1, "Nothing here.")])

        let hits = search.search("review", in: [byTitle, bySegment, none, byNote, bySummary])

        #expect(hits.map(\.meetingID) == [byTitle, bySegment, byNote, bySummary].map(\.meeting.id))
        #expect(hits.map(\.snippets) == [
            [],
            [SearchSnippet(source: .transcript, time: 5, text: "The review is on Friday.")],
            [SearchSnippet(source: .note, time: 7, text: "Prep Review deck")],
            [SearchSnippet(source: .summary, time: nil, text: "A short reVIEW of the plan.")],
        ])
        #expect(search.search("  ", in: [byTitle]).isEmpty)
    }

    @Test func atMostTwoSnippetsPerMeeting() {
        let loaded = MeetingFixtures.make(
            segments: [segment(1, "cap one"), segment(2, "cap two"), segment(3, "cap three")],
            notes: [Note(time: 4, text: "cap note", createdAt: created)]
        )
        let hits = search.search("CAP", in: [loaded])

        #expect(hits.map { $0.snippets.map(\.text) } == [["cap one", "cap two"]])
    }

    @Test func snippetsOrderTranscriptThenNoteThenSummaryByTime() {
        let late = MeetingFixtures.make(
            segments: [segment(300, "demo at noon")],
            notes: [Note(time: 10, text: "demo first", createdAt: created)],
            summary: summary("## Decisions\n\n- **Marta**: the demo moves.")
        )
        let noNoteMatch = MeetingFixtures.make(
            segments: [segment(1, "nothing")],
            notes: [Note(time: 2, text: "other", createdAt: created)],
            summary: summary("## Decisions\n\n- **Marta**: the demo moves.")
        )
        let unordered = MeetingFixtures.make(segments: [segment(90, "demo later"), segment(30, "demo earlier")])

        let hits = search.search("demo", in: [late, noNoteMatch, unordered])

        #expect(hits.map(\.snippets) == [
            [
                SearchSnippet(source: .transcript, time: 300, text: "demo at noon"),
                SearchSnippet(source: .note, time: 10, text: "demo first"),
            ],
            [SearchSnippet(source: .summary, time: nil, text: "Marta: the demo moves.")],
            [
                SearchSnippet(source: .transcript, time: 30, text: "demo earlier"),
                SearchSnippet(source: .transcript, time: 90, text: "demo later"),
            ],
        ])
    }

    @Test func summaryHeadingsDoNotMatch() {
        let loaded = MeetingFixtures.make(summary: summary("## Decisions\n\n- None."))
        #expect(search.search("decisions", in: [loaded]).isEmpty)
    }

    @Test func titleOnlyMatchListsTheMeetingWithoutSnippets() {
        let loaded = MeetingFixtures.make(title: "Northwind sync", segments: [segment(1, "hello")])
        #expect(search.search("northwind", in: [loaded]) == [SearchHit(meetingID: loaded.meeting.id, snippets: [])])
    }

    @Test func longTextIsCutAroundTheMatchAtWordBoundaries() {
        let text = "One two three four five six seven eight nine ten eleven twelve "
            + "Northwind thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty"
        let loaded = MeetingFixtures.make(segments: [segment(1, text)])
        let snippet = search.search("northwind", in: [loaded]).first?.snippets.first?.text

        #expect(snippet == "…six seven eight nine ten eleven twelve Northwind thirteen fourteen fifteen sixteen…")
    }

    @Test func excerptKeeps90CharactersOfContext() {
        let before = (1...30).map { String(format: "w%02d", $0) }
        let after = (1...30).map { String(format: "x%02d", $0) }
        let text = (before + ["Northwind"] + after).joined(separator: " ")
        func cut(dropping leading: Int, keeping trailing: Int) -> String {
            let words: [String] = before.dropFirst(leading) + ["Northwind"] + after.prefix(trailing)
            return "…" + words.joined(separator: " ") + "…"
        }

        #expect(SearchExcerpt.around("northwind", in: text, context: 90) == cut(dropping: 8, keeping: 22))
        #expect(SearchExcerpt.around("northwind", in: text, context: 40) == cut(dropping: 20, keeping: 10))
        #expect(SearchExcerpt.around("W01", in: "w01  w02\nw03", context: 90) == "w01 w02 w03")
        #expect(SearchExcerpt.around("absent", in: text, context: 90) == nil)
    }
}
