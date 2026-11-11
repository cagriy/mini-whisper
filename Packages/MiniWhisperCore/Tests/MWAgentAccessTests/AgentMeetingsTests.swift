import Foundation
import MWTestSupport
import Testing

import MWAgentAccess
import MWMeetings

/// `SeededMeetings` plus one test meeting, newest of all. Its transcript says "migration", as
/// the Northwind meeting's does, so an unfiltered search would hit it.
private struct SeededWithTestCall {
    static let testID = UUID(uuidString: "c0ffee00-5e1f-4a7b-9c3d-2e8f6a1b4c50")!
    static let title = "Test call · Release handover"

    let seeded: SeededMeetings
    let reader: AgentMeetings

    var store: MeetingStore { seeded.store }

    init() async throws {
        seeded = try await SeededMeetings()
        let test = MeetingFixtures.make(
            id: Self.testID, title: Self.title,
            startedAt: Date(timeIntervalSince1970: 1_794_304_800),  // 2026-11-10T10:00:00Z
            segments: [Segment(speaker: 0, start: 2, end: 6, text: "Did the migration finish overnight?", session: 1)],
            test: TestCallTag(scenarioID: "release-handover", revision: 1, scenarioTitle: "Release handover")
        )
        try await seeded.store.create(test.meeting)
        try await seeded.store.rewriteSegments(test.segments, of: Self.testID)
        reader = AgentMeetings(seeded.store)
    }
}

@Suite struct AgentMeetingsTests {
    private let testID = SeededWithTestCall.testID
    private var fullID: String { testID.uuidString.lowercased() }
    private var prefix: String { String(fullID.prefix(MeetingID.minimumPrefixDigits)) }

    private struct Output {
        var status: Int32
        var out: String
        var err: String
    }

    private func run(_ arguments: [String], _ reader: any MeetingReading) -> Output {
        let cli = MeetingsCLI(reader: reader, generator: "Mini Whisper 0.6.0", timeZone: TimeZone(identifier: "UTC")!)
        var out = ""
        var err = ""
        let status = cli.run(arguments, out: { out += $0 }, err: { err += $0 })
        return Output(status: status, out: out, err: err)
    }

    /// The `tools/call` result's text and `isError`.
    private func call(_ server: MCPServer, _ tool: String, _ arguments: [String: Any] = [:]) throws -> (text: String, isError: Bool) {
        let request: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": arguments],
        ]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let reply = try #require(server.handle(line: line))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        let result = try #require(object["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        return (try #require(content.first?["text"] as? String), try #require(result["isError"] as? Bool))
    }

    @Test func indexHidesTestMeetings() async throws {
        let seeded = try await SeededWithTestCall()
        try #require(try seeded.store.index().contains { $0.id == testID })

        let entries = try seeded.reader.index()

        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.test == nil })
        #expect(entries == (try seeded.store.index().filter { $0.id != testID }))
    }

    @Test func loadOfATestMeetingThrowsAsForAMissingOne() async throws {
        let seeded = try await SeededWithTestCall()
        func code(_ load: () throws -> LoadedMeeting) -> CocoaError.Code? {
            do {
                _ = try load()
                return nil
            } catch {
                return (error as? CocoaError)?.code
            }
        }

        let missing = code { try seeded.store.load(UUID()) }
        let hidden = code { try seeded.reader.load(testID) }

        #expect(missing == .fileReadNoSuchFile)
        #expect(hidden == missing)
        #expect(try seeded.reader.load(MeetingFixtures.northwindID) == seeded.store.load(MeetingFixtures.northwindID))
    }

    @Test func cliListAndSearchNeverShowATestMeeting() async throws {
        let seeded = try await SeededWithTestCall()
        try #require(run(["search", "migration"], seeded.store).out.contains(fullID))

        for arguments in [["list"], ["list", "--json"], ["search", "migration"], ["search", "migration", "--json"]] {
            let output = run(arguments, seeded.reader)
            #expect(output.status == 0, "\(arguments)")
            #expect(!output.out.isEmpty, "\(arguments)")
            #expect(!output.out.lowercased().contains(fullID), "\(arguments)")
            #expect(!output.out.contains(SeededWithTestCall.title), "\(arguments)")
        }
    }

    @Test func cliLookupByIDOrPrefixReportsNoMeeting() async throws {
        let seeded = try await SeededWithTestCall()

        for command in ["transcript", "summary"] {
            for id in [fullID, prefix] {
                let output = run([command, id], seeded.reader)
                #expect(output.status == 2, "\(command) \(id)")
                #expect(output.out.isEmpty, "\(command) \(id)")
                #expect(output.err == "no meeting \(id)\n", "\(command) \(id)")
            }
        }
    }

    @Test func mcpNeverReturnsATestMeeting() async throws {
        let seeded = try await SeededWithTestCall()
        let server = MCPServer(reader: seeded.reader, version: "0.6.0", timeZone: TimeZone(identifier: "UTC")!)
        let unknown = "00000000-0000-4000-8000-000000000000"

        let listed = try call(server, "list_meetings")
        let found = try call(server, "search_meetings", ["query": "migration"])
        #expect(!listed.isError && !found.isError)
        #expect(!listed.text.lowercased().contains(fullID))
        #expect(!found.text.lowercased().contains(fullID))
        #expect(try JSONDecoder().decode([SearchHit].self, from: Data(found.text.utf8)).map(\.meetingID)
            == [MeetingFixtures.northwindID, SeededMeetings.standupID])

        for tool in ["get_transcript", "get_summary"] {
            let asUnknown = try call(server, tool, ["id": unknown])
            #expect(asUnknown.isError)
            for id in [fullID, prefix] {
                let hidden = try call(server, tool, ["id": id])
                #expect(hidden.isError, "\(tool) \(id)")
                #expect(hidden.text == asUnknown.text.replacingOccurrences(of: unknown, with: id), "\(tool) \(id)")
            }
        }
    }
}
