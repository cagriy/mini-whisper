import Foundation
import MWConfig
import MWSupport
import MWTestSupport
import Testing

import MWAgentAccess
import MWMeetings

/// A reader over meetings held in memory; it has no write API to reach.
private struct InMemoryReader: MeetingReading {
    let meetings: [LoadedMeeting]

    func index() throws -> [IndexEntry] {
        meetings.map {
            IndexEntry(
                id: $0.meeting.id, title: $0.meeting.title, startedAt: $0.meeting.startedAt, endedAt: nil,
                duration: 0, mode: .remote, app: nil, engine: .speechmaticsStandard, speakerCount: 1,
                costUSD: 0, hasSummary: false, audioBytes: 0, excerpt: ""
            )
        }
    }

    func load(_ id: UUID) throws -> LoadedMeeting {
        guard let loaded = meetings.first(where: { $0.meeting.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        return loaded
    }
}

@Suite struct MCPServerTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let generator = "Mini Whisper 0.6.0"
    private let northwind = MeetingFixtures.northwindID.uuidString.lowercased()
    private var modernMeta: [String: Any] {
        [
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientCapabilities": [String: Any](),
        ]
    }

    private struct ToolResult: Equatable {
        var text: String
        var isError: Bool
    }

    private func server(_ reader: any MeetingReading) -> MCPServer {
        MCPServer(reader: reader, version: "0.6.0", timeZone: utc)
    }

    private func line(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func request(_ id: Int, _ method: String, _ params: [String: Any]? = nil) throws -> String {
        var object: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        object["params"] = params
        return try line(object)
    }

    private func reply(_ server: MCPServer, _ line: String) throws -> [String: Any] {
        let text = try #require(server.handle(line: line))
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func result(_ server: MCPServer, _ line: String) throws -> [String: Any] {
        let response = try reply(server, line)
        #expect(response["jsonrpc"] as? String == "2.0")
        #expect(response["error"] == nil)
        return try #require(response["result"] as? [String: Any])
    }

    private func error(_ server: MCPServer, _ line: String) throws -> [String: Any] {
        let response = try reply(server, line)
        #expect(response["result"] == nil)
        return try #require(response["error"] as? [String: Any])
    }

    private func call(
        _ server: MCPServer, _ tool: String, _ arguments: [String: Any] = [:]
    ) throws -> ToolResult {
        let result = try result(server, try request(9, "tools/call", ["name": tool, "arguments": arguments]))
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.count == 1)
        #expect(content.first?["type"] as? String == "text")
        return ToolResult(
            text: try #require(content.first?["text"] as? String), isError: try #require(result["isError"] as? Bool)
        )
    }

    private func initialize(_ version: String) throws -> [String: Any] {
        let reader = InMemoryReader(meetings: [])
        return try result(server(reader), try request(1, "initialize", [
            "protocolVersion": version, "capabilities": [String: Any](),
            "clientInfo": ["name": "claude-code", "version": "2.1.0"],
        ]))
    }

    // MARK: Handshake and discovery

    @Test func initializeEchoes20251125() throws {
        let result = try initialize("2025-11-25")

        #expect(result["protocolVersion"] as? String == "2025-11-25")
        #expect((result["capabilities"] as? [String: Any])?["tools"] as? [String: Any] != nil)
        #expect(result["serverInfo"] as? [String: String] == ["name": "mini-whisper", "version": "0.6.0"])
        #expect(result["resultType"] == nil)
    }

    @Test func initializeEchoes20250618() throws {
        #expect(try initialize("2025-06-18")["protocolVersion"] as? String == "2025-06-18")
    }

    @Test func initializeWithAnUnknownVersionAnswers20251125() throws {
        for version in ["2024-11-05", "2026-07-28", "banana"] {
            #expect(try initialize(version)["protocolVersion"] as? String == "2025-11-25", "\(version)")
        }
    }

    @Test func initializedNotificationGetsNoReply() throws {
        let server = server(InMemoryReader(meetings: []))

        #expect(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{}}"#) == nil)
        #expect(server.handle(line: #"{"jsonrpc":"2.0","method":"no/such/notification"}"#) == nil)
    }

    @Test func pingReturnsAnEmptyObject() throws {
        let response = try reply(server(InMemoryReader(meetings: [])), try request(4, "ping"))

        #expect(response["id"] as? Int == 4)
        #expect((response["result"] as? [String: Any])?.isEmpty == true)
    }

    @Test func serverDiscoverReturnsCompleteWithVersionsCapabilitiesAndServerInfo() throws {
        let result = try result(
            server(InMemoryReader(meetings: [])), try request(2, "server/discover", ["_meta": modernMeta])
        )

        #expect(result["resultType"] as? String == "complete")
        #expect(result["supportedVersions"] as? [String] == ["2026-07-28", "2025-11-25", "2025-06-18"])
        #expect((result["capabilities"] as? [String: Any])?["tools"] as? [String: Any] != nil)
        let meta = try #require(result["_meta"] as? [String: Any])
        #expect(meta["io.modelcontextprotocol/serverInfo"] as? [String: String]
            == ["name": "mini-whisper", "version": "0.6.0"])
        #expect(result["ttlMs"] as? Int == 0)
        #expect(result["cacheScope"] as? String == "private")
    }

    @Test func toolsListHasFourReadOnlyToolsWithSchemas() throws {
        let result = try result(server(InMemoryReader(meetings: [])), try request(3, "tools/list"))
        let tools = try #require(result["tools"] as? [[String: Any]])

        #expect(tools.compactMap { $0["name"] as? String }
            == ["list_meetings", "get_transcript", "get_summary", "search_meetings"])
        for tool in tools {
            let annotations = try #require(tool["annotations"] as? [String: Any])
            #expect(annotations["readOnlyHint"] as? Bool == true)
            #expect(annotations["openWorldHint"] as? Bool == false)
            #expect(!(tool["description"] as? String ?? "").isEmpty)
            let schema = try #require(tool["inputSchema"] as? [String: Any])
            #expect(schema["type"] as? String == "object")
            #expect(schema["additionalProperties"] as? Bool == false)
        }
        let schemas = tools.map { $0["inputSchema"] as? [String: Any] ?? [:] }
        #expect(schemas[0]["required"] == nil)
        #expect(schemas[1]["required"] as? [String] == ["id"])
        #expect(schemas[2]["required"] as? [String] == ["id"])
        #expect(schemas[3]["required"] as? [String] == ["query"])
        let search = try #require(schemas[3]["properties"] as? [String: [String: Any]])
        #expect(search["query"]?["type"] as? String == "string")
        #expect(search["limit"]?["type"] as? String == "integer")
        #expect(search["limit"]?["minimum"] as? Int == 1)
        #expect(search["limit"]?["maximum"] as? Int == 50)
        let id = try #require((schemas[1]["properties"] as? [String: [String: Any]])?["id"])
        #expect(id["type"] as? String == "string")
        #expect(id["maxLength"] as? Int == 10_000)
        #expect(result["resultType"] == nil)
    }

    // MARK: Tools

    @Test func listMeetingsReturnsText() async throws {
        let seeded = try await SeededMeetings()

        let result = try call(server(seeded.store), "list_meetings")

        #expect(!result.isError)
        let entries = try MeetingCoding.decoder().decode([IndexEntry].self, from: Data(result.text.utf8))
        #expect(entries == (try seeded.store.index()))
        #expect(entries.count == 3)
    }

    @Test func getTranscriptReturnsTheMarkdown() async throws {
        let seeded = try await SeededMeetings()
        let server = server(seeded.store)

        let byID = try call(server, "get_transcript", ["id": northwind])
        let byPrefix = try call(server, "get_transcript", ["id": "B52E04A1"])

        #expect(byID == ToolResult(text: MeetingMarkdown.transcript(
            try seeded.store.load(MeetingFixtures.northwindID), generator: generator, timeZone: utc
        ), isError: false))
        #expect(byPrefix == ToolResult(text: MeetingMarkdown.transcript(
            try seeded.store.load(SeededMeetings.standupID), generator: generator, timeZone: utc
        ), isError: false))
    }

    @Test func getSummaryReturnsTheMarkdown() async throws {
        let seeded = try await SeededMeetings()

        let summary = try call(server(seeded.store), "get_summary", ["id": "7f3a9c2e-5b1d"])

        #expect(summary == ToolResult(text: try MeetingMarkdown.summary(
            try seeded.store.load(MeetingFixtures.northwindID), generator: generator, timeZone: utc
        ), isError: false))
    }

    @Test func getSummaryWithoutOneIsAnError() async throws {
        let seeded = try await SeededMeetings()

        let summary = try call(server(seeded.store), "get_summary", ["id": "b52e04a1"])

        #expect(summary == ToolResult(text: "no summary for meeting b52e04a1", isError: true))
    }

    @Test func badUnknownAndAmbiguousIdsAreToolErrors() async throws {
        let seeded = try await SeededMeetings()
        let server = server(seeded.store)
        func failed(_ text: String) -> ToolResult { ToolResult(text: text, isError: true) }

        #expect(try call(server, "get_transcript", ["id": "../etc"])
            == failed("invalid meeting id ../etc: use a UUID or at least its first 8 hex characters"))
        #expect(try call(server, "get_transcript", ["id": "0000000a"]) == failed("no meeting 0000000a"))
        #expect(try call(server, "get_summary", ["id": "7f3a9c2e"]) == failed("ambiguous meeting id 7f3a9c2e"))
    }

    @Test func missingOrMistypedArgumentsAreToolErrors() async throws {
        let seeded = try await SeededMeetings()
        let server = server(seeded.store)

        let missing = try call(server, "get_transcript")
        let mistyped = try call(server, "search_meetings", ["query": "budget", "limit": "ten"])

        #expect(missing.isError)
        #expect(missing.text.contains("get_transcript"))
        #expect(mistyped.isError)
        #expect(mistyped.text.contains("search_meetings"))
    }

    @Test func searchMeetingsReturnsTheHits() async throws {
        let seeded = try await SeededMeetings()
        let reader = seeded.store

        let result = try call(server(reader), "search_meetings", ["query": "build is green"])

        #expect(!result.isError)
        let hits = try JSONDecoder().decode([SearchHit].self, from: Data(result.text.utf8))
        let all = try reader.index().map { try reader.load($0.id) }
        #expect(hits == MeetingSearch().search("build is green", in: all))
        #expect(hits.map(\.meetingID) == [SeededMeetings.standupID])
    }

    @Test func searchMeetingsCapsLimitAt50() throws {
        let meetings = (0..<60).map { index in
            MeetingFixtures.make(title: "Budget review \(index)")
        }
        let server = server(InMemoryReader(meetings: meetings))
        func count(_ arguments: [String: Any]) throws -> Int {
            let result = try call(server, "search_meetings", arguments)
            #expect(!result.isError)
            return try JSONDecoder().decode([SearchHit].self, from: Data(result.text.utf8)).count
        }

        #expect(try count(["query": "budget"]) == 50)
        #expect(try count(["query": "budget", "limit": 500]) == 50)
        #expect(try count(["query": "budget", "limit": 3]) == 3)
        #expect(try count(["query": "budget", "limit": 0]) == 1)
    }

    @Test func unknownToolIsAnError() throws {
        let error = try error(
            server(InMemoryReader(meetings: [])), try request(5, "tools/call", ["name": "delete_meeting"])
        )

        #expect(error["code"] as? Int == -32602)
        #expect(error["message"] as? String == "Unknown tool: delete_meeting")
    }

    // MARK: Errors

    @Test func unknownMethodIsMinus32601() throws {
        let server = server(InMemoryReader(meetings: []))

        let response = try reply(server, try request(6, "resources/list"))

        #expect(response["id"] as? Int == 6)
        #expect((response["error"] as? [String: Any])?["code"] as? Int == -32601)
    }

    @Test func malformedJSONIsMinus32700AndTheLoopContinues() throws {
        let server = server(InMemoryReader(meetings: []))
        var lines = ["{\"jsonrpc\":\"2.0\",\"id\":1,", try request(2, "ping")][...]
        var written: [String] = []

        let status = server.run(readLine: { lines.popFirst() }, write: { written.append($0) })

        #expect(status == 0)
        try #require(written.count == 2)
        let first = try #require(
            try JSONSerialization.jsonObject(with: Data(written[0].utf8)) as? [String: Any]
        )
        #expect((first["error"] as? [String: Any])?["code"] as? Int == -32700)
        #expect(first["id"] == nil)
        #expect(written[1].contains(#""id":2"#))
        #expect(written[1].contains(#""result":{}"#))
    }

    @Test func invalidRequestsAreMinus32600() throws {
        let server = server(InMemoryReader(meetings: []))

        let noMethod = try reply(server, #"{"jsonrpc":"2.0","id":7}"#)
        let nullID = try reply(server, #"{"jsonrpc":"2.0","id":null,"method":"ping"}"#)
        let badVersion = try reply(server, #"{"jsonrpc":"1.0","id":"a","method":"ping"}"#)
        let batch = try reply(server, #"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#)

        #expect(noMethod["id"] as? Int == 7)
        #expect(nullID["id"] == nil)
        #expect(badVersion["id"] as? String == "a")
        #expect(batch["id"] == nil)
        for response in [noMethod, nullID, badVersion, batch] {
            #expect((response["error"] as? [String: Any])?["code"] as? Int == -32600)
        }
    }

    @Test func metaVersion20260728IsServed() throws {
        let server = server(InMemoryReader(meetings: []))

        let list = try result(server, try request(3, "tools/list", ["_meta": modernMeta]))
        let call = try result(server, try request(4, "tools/call", [
            "name": "list_meetings", "arguments": [String: Any](), "_meta": modernMeta,
        ]))

        #expect((list["tools"] as? [Any])?.count == 4)
        for result in [list, call] {
            #expect(result["resultType"] as? String == "complete")
            #expect((result["_meta"] as? [String: Any])?["io.modelcontextprotocol/serverInfo"] != nil)
        }
        #expect(list["ttlMs"] as? Int == 0)
        #expect(list["cacheScope"] as? String == "private")
        #expect(call["isError"] as? Bool == false)
        #expect(call["ttlMs"] == nil)
    }

    @Test func otherMetaVersionIsMinus32022WithSupportedAndRequested() throws {
        var meta = modernMeta
        meta["io.modelcontextprotocol/protocolVersion"] = "2025-11-25"

        let error = try error(
            server(InMemoryReader(meetings: [])), try request(8, "tools/list", ["_meta": meta])
        )

        #expect(error["code"] as? Int == -32022)
        #expect(error["message"] as? String == "Unsupported protocol version")
        let data = try #require(error["data"] as? [String: Any])
        #expect(data["supported"] as? [String] == ["2026-07-28", "2025-11-25", "2025-06-18"])
        #expect(data["requested"] as? String == "2025-11-25")
    }

    @Test func modernRequestWithoutClientCapabilitiesIsMinus32602() throws {
        let meta = ["io.modelcontextprotocol/protocolVersion": "2026-07-28"]

        let error = try error(
            server(InMemoryReader(meetings: [])), try request(8, "tools/list", ["_meta": meta])
        )

        #expect(error["code"] as? Int == -32602)
    }

    @Test func stringsOver10000CharactersAreInvalidParams() async throws {
        let seeded = try await SeededMeetings()
        let server = server(seeded.store)
        let long = String(repeating: "a", count: 10_001)
        let limit = String(repeating: "a", count: 10_000)

        let requests = [
            try request(1, "tools/call", ["name": "get_transcript", "arguments": ["id": long]]),
            try request(2, "tools/call", ["name": "search_meetings", "arguments": ["query": long]]),
            try request(3, "tools/call", ["name": long]),
            try request(4, "initialize", ["protocolVersion": long, "capabilities": [String: Any]()]),
            try request(5, "tools/list", ["_meta": [
                "io.modelcontextprotocol/protocolVersion": long,
                "io.modelcontextprotocol/clientCapabilities": [String: Any](),
            ]]),
        ]
        for line in requests {
            #expect(try error(server, line)["code"] as? Int == -32602)
        }
        #expect(try call(server, "search_meetings", ["query": limit]) == ToolResult(text: "[]", isError: false))
    }

    // MARK: Framing and logging

    @Test func everyResponseIsOneLine() async throws {
        let seeded = try await SeededMeetings()
        var lines = [
            try request(1, "initialize", ["protocolVersion": "2025-11-25", "capabilities": [String: Any]()]),
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            try request(2, "tools/list"),
            try request(3, "server/discover", ["_meta": modernMeta]),
            try request(4, "tools/call", ["name": "get_transcript", "arguments": ["id": northwind]]),
            try request(5, "tools/call", ["name": "get_summary", "arguments": ["id": northwind]]),
            try request(6, "tools/call", ["name": "search_meetings", "arguments": ["query": "the"]]),
            try request(7, "tools/call", ["name": "list_meetings"]),
            "not json",
            try request(8, "nope"),
            try request(9, "tools/call", ["name": "a\u{2028}b\u{2029}c\u{85}d"]),
        ][...]
        var written: [String] = []

        _ = server(seeded.store).run(readLine: { lines.popFirst() }, write: { written.append($0) })

        try #require(written.count == 10)
        for text in written {
            #expect(text.hasSuffix("\n"))
            #expect(text.dropLast().allSatisfy { !$0.isNewline })
            #expect(try JSONSerialization.jsonObject(with: Data(text.utf8)) is [String: Any])
        }
        #expect(written[3].contains(#"\n"#))
    }

    @Test func eofExitsZero() {
        var written: [String] = []

        let status = server(InMemoryReader(meetings: [])).run(readLine: { nil }, write: { written.append($0) })

        #expect(status == 0)
        #expect(written.isEmpty)
    }

    @Test func logsMethodAndToolNamesOnly() async throws {
        let seeded = try await SeededMeetings()
        let sink = CapturingLogSink()
        let server = server(seeded.store)

        try await Log.withSinks(debug: true, sinks: [sink]) {
            _ = try call(server, "search_meetings", ["query": "private words"])
            _ = server.handle(line: try request(2, "private/method"))
        }

        #expect(sink.lines == ["INFO meeting mcp: tools/call search_meetings", "INFO meeting mcp: unknown method"])
    }
}
