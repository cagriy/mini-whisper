import Foundation
import MWAgentAccess
import MWMeetings
import Testing
@testable import MiniWhisper

@Suite struct MeetingExporterTests {
    private static let utc = TimeZone(identifier: "UTC")!
    private static let generator = "Mini Whisper 0.5.0"

    private let exporter = MeetingExporter(generator: Self.generator, timeZone: Self.utc)

    private static func meeting(title: String = "Q3: plan/review", summarised: Bool = true) -> LoadedMeeting {
        let startedAt = Date(timeIntervalSince1970: 1_794_234_600)
        let summary = Summary(
            text: "## Summary\nShip on Wednesday.\n\n## Decisions\n- Wednesday.\n\n## Action items\n- None.\n\n## Open questions\n- None.",
            model: "claude-sonnet-5-5",
            createdAt: startedAt.addingTimeInterval(700),
            inputTokens: 900,
            outputTokens: 120,
            costUSD: 0.003
        )
        let meeting = Meeting(
            title: title, startedAt: startedAt, endedAt: startedAt.addingTimeInterval(600), durationSeconds: 600,
            mode: .remote, app: "Zoom", engine: .speechmaticsStandard, userName: "Alex",
            speakers: [SpeakerLabel(id: 0, name: "Alex", isUser: true), SpeakerLabel(id: 1, name: "Marta")],
            summary: summarised ? summary : nil
        )
        return LoadedMeeting(
            meeting: meeting,
            segments: [
                Segment(speaker: 1, start: 4, end: 8, text: "Can we ship on Wednesday?", session: 1),
                Segment(speaker: 0, start: 9, end: 11, text: "Yes.", session: 1),
            ],
            notes: [Note(time: 6, text: "Ask ops", createdAt: startedAt.addingTimeInterval(6))]
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingExporterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func contents(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    @Test func suggestedNamesUseTheSanitisedStem() {
        let names = MeetingExporter.suggestedNames(title: "Q3: plan/review")
        #expect(names.transcript == "Q3- plan-review - transcript.md")
        #expect(names.summary == "Q3- plan-review - summary.md")
    }

    @Test func exportTranscriptWritesMeetingMarkdown() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let meeting = Self.meeting()
        let url = folder.appendingPathComponent("out.md")

        try exporter.writeTranscript(meeting, to: url)

        let expected = MeetingMarkdown.transcript(meeting, generator: Self.generator, timeZone: Self.utc)
        #expect(try contents(url) == expected)
        #expect(exporter.transcript(meeting) == expected)
    }

    @Test func exportBothWritesTwoFilesIntoTheFolder() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let meeting = Self.meeting()

        let written = try exporter.writeBoth(meeting, folder: folder)

        let transcript = folder.appendingPathComponent("Q3- plan-review - transcript.md")
        let summary = folder.appendingPathComponent("Q3- plan-review - summary.md")
        #expect(written == [transcript, summary])
        #expect(try contents(transcript) == exporter.transcript(meeting))
        #expect(try contents(summary) == MeetingMarkdown.summary(meeting, generator: Self.generator, timeZone: Self.utc))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            == ["Q3- plan-review - summary.md", "Q3- plan-review - transcript.md"])
    }

    @Test func exportSummaryWithoutOneIsRefused() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let meeting = Self.meeting(summarised: false)

        #expect(throws: MeetingExporter.Refusal.noSummary) { try exporter.summary(meeting) }
        #expect(throws: MeetingExporter.Refusal.noSummary) {
            try exporter.writeSummary(meeting, to: folder.appendingPathComponent("s.md"))
        }
        #expect(throws: MeetingExporter.Refusal.noSummary) { try exporter.writeBoth(meeting, folder: folder) }
        #expect(MeetingExporter.Refusal.noSummary.errorDescription == "This meeting has no summary yet.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    /// Plan Stage 25's definition of done: exported text equals `meetings transcript <id>`.
    @Test func exportedTextEqualsTheCLIs() {
        let meeting = Self.meeting()
        let exporter = MeetingExporter(generator: Self.generator)
        var transcript = ""
        var summary = ""
        let cli = MeetingsCLI(reader: OneMeeting(meeting: meeting), generator: Self.generator)
        let id = meeting.meeting.id.uuidString

        #expect(cli.run(["transcript", id], out: { transcript += $0 }, err: { _ in }) == 0)
        #expect(cli.run(["summary", id], out: { summary += $0 }, err: { _ in }) == 0)
        #expect(transcript == exporter.transcript(meeting))
        #expect(summary == (try? exporter.summary(meeting)))
    }

    private struct OneMeeting: MeetingReading {
        let meeting: LoadedMeeting

        func index() throws -> [IndexEntry] {
            let m = meeting.meeting
            return [IndexEntry(
                id: m.id, title: m.title, startedAt: m.startedAt, endedAt: m.endedAt, duration: m.durationSeconds,
                mode: m.mode, app: m.app, engine: m.engine, speakerCount: m.speakers.count, costUSD: 0,
                hasSummary: m.summary != nil, audioBytes: 0, excerpt: ""
            )]
        }

        func load(_ id: UUID) throws -> LoadedMeeting { meeting }
    }
}
