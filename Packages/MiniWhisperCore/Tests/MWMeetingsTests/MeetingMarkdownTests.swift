import Foundation
import MWTestSupport
import Testing

import MWMeetings

@Suite struct MeetingMarkdownTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let generator = "Mini Whisper 0.6.0"

    private func golden(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Fixtures/golden")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func segment(_ speaker: Int, _ start: Double, _ text: String) -> Segment {
        Segment(speaker: speaker, start: start, end: start + 2, text: text, session: 1)
    }

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    @Test func transcriptMatchesTheGolden() throws {
        let text = MeetingMarkdown.transcript(MeetingFixtures.northwind(), generator: generator, timeZone: utc)
        #expect(text == (try golden("northwind-transcript")))
    }

    @Test func summaryMatchesTheGolden() throws {
        let text = try MeetingMarkdown.summary(MeetingFixtures.northwind(), generator: generator, timeZone: utc)
        #expect(text == (try golden("northwind-summary")))
    }

    @Test func summaryWithoutASummaryThrows() {
        #expect(throws: MeetingMarkdownError.noSummary) {
            try MeetingMarkdown.summary(MeetingFixtures.make(), generator: generator, timeZone: utc)
        }
    }

    @Test func sleepPauseAddsMacSlept() {
        var loaded = MeetingFixtures.make()
        loaded.meeting.markers = [
            Marker(kind: .paused, start: 60, end: 75),
            Marker(kind: .sleep, start: 3600, end: 3725),
        ]
        let text = lines(MeetingMarkdown.transcript(loaded, generator: generator, timeZone: utc))

        #expect(text.contains("> **Paused** · 00:01:00–00:01:15"))
        #expect(text.contains("> **Paused** · 01:00:00–01:02:05 · Mac slept"))
    }

    @Test func meetingTimeFormatsHHMMSS() {
        #expect(MeetingTime.format(0) == "00:00:00")
        #expect(MeetingTime.format(2342.9) == "00:39:02")
        #expect(MeetingTime.format(3725) == "01:02:05")
        #expect(MeetingTime.format(-3) == "00:00:00")
    }

    @Test func transcriptBodyIsTheTranscriptSectionOnly() throws {
        let section = try #require(try golden("northwind-transcript").components(separatedBy: "## Transcript\n\n").last)
        let withoutNotes = section
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: "\n\n")
            .filter { !$0.hasPrefix("> **Note**") }
            .joined(separator: "\n\n")

        #expect(MeetingMarkdown.transcriptBody(MeetingFixtures.northwind()) == withoutNotes)
    }

    @Test func consecutiveSegmentsOfOneSpeakerMergeUntilANoteOrMarker() {
        var loaded = MeetingFixtures.make(
            segments: [segment(0, 10, "One."), segment(0, 13, "Two."), segment(1, 20, "Three."),
                       segment(1, 40, "Four."), segment(1, 60, "Five.")],
            notes: [Note(time: 30, text: "first line\nsecond line", createdAt: Date(timeIntervalSince1970: 0))]
        )
        loaded.meeting.speakers.append(SpeakerLabel(id: 1, name: "Speaker 1"))
        loaded.meeting.markers = [Marker(kind: .gap, start: 50, end: 55, reason: "connection lost")]

        #expect(MeetingMarkdown.transcriptBody(loaded) == """
            **Alex** · 00:00:10
            One. Two.

            **Speaker 1** · 00:00:20
            Three. Four.

            > **Gap** · 00:00:50–00:00:55 · connection lost, audio kept

            **Speaker 1** · 00:01:00
            Five.
            """)
        #expect(MeetingMarkdown.transcript(loaded, generator: generator, timeZone: utc).contains("""
            Three.

            > **Note** · 00:00:30 · first line
            > second line

            **Speaker 1** · 00:00:40
            Four.
            """))
    }

    @Test func frontMatterQuotesWhatYAMLWouldMisread() {
        var loaded = MeetingFixtures.make(title: "Q3: pricing #2", segments: [segment(0, 1, "Hi.")])
        loaded.meeting.speakers[0].name = "Smith, J."
        loaded.meeting.app = "2026"
        let text = lines(MeetingMarkdown.transcript(loaded, generator: generator, timeZone: utc))

        #expect(text.contains(#"title: "Q3: pricing #2""#))
        #expect(text.contains(#"app: "2026""#))
        #expect(text.contains(#"speakers: ["Smith, J."]"#))
        #expect(text.contains("# Q3: pricing #2"))
    }

    @Test func inRoomMeetingWithoutAppOrEnd() {
        var loaded = MeetingFixtures.make(mode: .inRoom)
        loaded.meeting.app = nil
        loaded.meeting.durationSeconds = 1500
        let text = lines(MeetingMarkdown.transcript(loaded, generator: generator, timeZone: utc))

        #expect(text.contains("mode: in-room"))
        #expect(!text.contains { $0.hasPrefix("app:") })
        #expect(text.contains(#"end: "11:25""#))
        #expect(text.contains("9 November 2026 · 11:00–11:25 · In the room"))
    }

    @Test func summaryFooterCountsAndNotesSection() throws {
        let summary = Summary(
            text: "## Summary\n\nShort.\n", model: "claude-opus-6", createdAt: Date(timeIntervalSince1970: 1_794_222_090),
            inputTokens: 1, outputTokens: 1, costUSD: 0
        )
        var loaded = MeetingFixtures.make(
            notes: [Note(time: 5, text: "one\ntwo", createdAt: Date(timeIntervalSince1970: 0))], summary: summary
        )
        loaded.meeting.durationSeconds = 119
        let withNote = try MeetingMarkdown.summary(loaded, generator: generator, timeZone: utc)

        #expect(withNote.contains("""
            Short.

            ## Notes

            - 00:00:05 · one
              two

            ---

            Summary by Claude Opus 6 at 11:01 from 1 minute of transcript and 1 note · \
            transcript: Zoom · 9 Nov 2026 11-00 - transcript.md

            """))

        loaded.notes = []
        loaded.meeting.summary?.model = "gpt-x"
        let withoutNotes = try MeetingMarkdown.summary(loaded, generator: generator, timeZone: utc)
        #expect(!withoutNotes.contains("## Notes"))
        #expect(withoutNotes.contains("Short.\n\n---\n\nSummary by gpt-x at 11:01 from 1 minute of transcript and 0 notes"))
    }
}
