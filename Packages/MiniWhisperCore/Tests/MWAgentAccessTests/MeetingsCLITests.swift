import Foundation
import MWSupport
import MWTestSupport
import Testing

import MWAgentAccess
import MWMeetings

@Suite struct MeetingsCLITests {
    private let generator = "Mini Whisper 0.6.0"
    private let utc = TimeZone(identifier: "UTC")!
    private let northwind = MeetingFixtures.northwindID.uuidString.lowercased()

    private struct Output {
        var status: Int32
        var out: String
        var err: String
    }

    private func run(_ arguments: [String], on seeded: SeededMeetings) -> Output {
        let cli = MeetingsCLI(reader: seeded.store, generator: generator, timeZone: utc)
        var out = ""
        var err = ""
        let status = cli.run(arguments, out: { out += $0 }, err: { err += $0 })
        return Output(status: status, out: out, err: err)
    }

    private func expectOneErrorLine(
        _ output: Output, _ line: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(output.status == 2, sourceLocation: sourceLocation)
        #expect(output.out.isEmpty, sourceLocation: sourceLocation)
        #expect(output.err == line + "\n", sourceLocation: sourceLocation)
    }

    @Test func listPrintsOneLinePerMeeting() async throws {
        let seeded = try await SeededMeetings()

        let output = run(["list"], on: seeded)

        #expect(output.status == 0)
        #expect(output.out == """
            7f3a9c2e-5b1d-4e0a-9c77-2d8f1a6b3c40  2026-11-09  14:30  00:48:52  Northwind rollout sync
            b52e04a1-3c7d-4f21-a8e9-5d0c6b7a1f22  2026-11-09  11:00  00:00:00  Zoom · 9 Nov 2026 11:00
            7f3a9c2e-9999-4999-8999-999999999999  2026-11-08  09:00  00:00:00  Planning

            """)
    }

    @Test func listJSONIsTheIndex() async throws {
        let seeded = try await SeededMeetings()

        let output = run(["list", "--json"], on: seeded)

        #expect(output.out.hasSuffix("]\n"))
        let decoded = try MeetingCoding.decoder().decode([IndexEntry].self, from: Data(output.out.utf8))
        #expect(decoded == (try seeded.store.index()))
        #expect(decoded.count == 3)
    }

    @Test func transcriptPrintsExactlyMeetingMarkdown() async throws {
        let seeded = try await SeededMeetings()

        let byID = run(["transcript", northwind], on: seeded)
        let byPrefix = run(["transcript", "b52e04a1"], on: seeded)

        let expected = MeetingMarkdown.transcript(
            try seeded.store.load(MeetingFixtures.northwindID), generator: generator, timeZone: utc
        )
        #expect(byID.out == expected)
        #expect(byPrefix.out == MeetingMarkdown.transcript(
            try seeded.store.load(SeededMeetings.standupID), generator: generator, timeZone: utc
        ))
    }

    @Test func summaryPrintsExactlyMeetingMarkdown() async throws {
        let seeded = try await SeededMeetings()

        let output = run(["summary", "7f3a9c2e-5b1d"], on: seeded)

        let expected = try MeetingMarkdown.summary(
            try seeded.store.load(MeetingFixtures.northwindID), generator: generator, timeZone: utc
        )
        #expect(output.out == expected)
    }

    @Test func summaryOfAMeetingWithoutOneExits2() async throws {
        let seeded = try await SeededMeetings()

        expectOneErrorLine(run(["summary", "b52e04a1"], on: seeded), "no summary for meeting b52e04a1")
    }

    @Test func searchPrintsIdTimeSourceSnippet() async throws {
        let seeded = try await SeededMeetings()

        let maintenance = run(["search", "maintenance"], on: seeded)
        #expect(maintenance.out == """
            \(northwind)  00:40:05  note  Ask ops for a Wednesday maintenance window
            \(northwind)  -  summary  Alex: ask ops for a Wednesday maintenance window.

            """)

        // Words are joined into one query; a title-only match prints the title.
        let lines = run(["search", "migration", "script"], on: seeded).out.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.first?.hasPrefix("\(northwind)  00:39:02  transcript  ") == true)
        #expect(lines.first?.contains("migration script") == true)
        #expect(lines.last == "\(northwind)  00:12:40  note  Marta owns the migration script; review by Thu")

        #expect(run(["search", "planning"], on: seeded).out == """
            7f3a9c2e-9999-4999-8999-999999999999  -  title  Planning

            """)
    }

    @Test func searchJSON() async throws {
        let seeded = try await SeededMeetings()

        let output = run(["search", "migration", "--json"], on: seeded)

        let decoded = try JSONDecoder().decode([SearchHit].self, from: Data(output.out.utf8))
        let loaded = try seeded.store.index().map { try seeded.store.load($0.id) }
        #expect(decoded == MeetingSearch().search("migration", in: loaded))
        #expect(decoded.map(\.meetingID) == [MeetingFixtures.northwindID, SeededMeetings.standupID])
    }

    @Test func unknownIdExits2WithOneStderrLine() async throws {
        let seeded = try await SeededMeetings()

        expectOneErrorLine(run(["transcript", "0123abcd"], on: seeded), "no meeting 0123abcd")
        let unknown = "00000000-0000-4000-8000-000000000000"
        expectOneErrorLine(run(["summary", unknown], on: seeded), "no meeting \(unknown)")
        expectOneErrorLine(
            run(["transcript", "../etc"], on: seeded),
            "invalid meeting id ../etc: use a UUID or at least its first 8 hex characters"
        )
        expectOneErrorLine(run(["transcript", "7f3a9c2e"], on: seeded), "ambiguous meeting id 7f3a9c2e")
    }

    @Test(arguments: [
        ["frobnicate"], [], ["list", "extra"], ["transcript"], ["transcript", "b52e04a1", "x"],
        ["summary"], ["search"], ["search", "--json"], ["search", " "],
    ])
    func unknownSubcommandExits2WithUsage(_ arguments: [String]) async throws {
        let seeded = try await SeededMeetings()

        let output = run(arguments, on: seeded)

        #expect(output.status == 2)
        #expect(output.out.isEmpty)
        #expect(output.err.hasPrefix("usage: mini-whisper meetings list [--json]\n"))
    }

    @Test func everyCommandExitsZeroOnSuccess() async throws {
        let seeded = try await SeededMeetings()
        let commands = [
            ["list"], ["list", "--json"], ["transcript", "b52e04a1"], ["summary", northwind],
            ["search", "build"], ["search", "build", "--json"], ["search", "nothing matches this"],
        ]

        for arguments in commands {
            let output = run(arguments, on: seeded)
            #expect(output.status == 0, "\(arguments)")
            #expect(output.err.isEmpty, "\(arguments)")
        }
    }

    @Test func logsTheCommandNameOnly() async throws {
        let seeded = try await SeededMeetings()
        let sink = CapturingLogSink()

        await Log.withSinks(debug: true, sinks: [sink]) {
            _ = run(["search", "private words"], on: seeded)
        }

        #expect(sink.lines == ["INFO meeting cli: search"])
    }
}
