import Foundation
import MWMeetings
import MWSupport

/// `mini-whisper mcp` (design §5.3, R21): a stdio JSON-RPC server, one message per line. It
/// answers MCP's `initialize` handshake (2025-11-25, 2025-06-18) and the stateless 2026-07-28
/// revision, which carries its version in each request's `_meta`. It is handed only a
/// `MeetingReading`, so no write is reachable.
public struct MCPServer: Sendable {
    private static let statelessVersion = "2026-07-28"
    private static let handshakeVersions = ["2025-11-25", "2025-06-18"]
    fileprivate static let supportedVersions = [statelessVersion] + handshakeVersions
    private static let searchLimit = 50

    private let reader: any MeetingReading
    private let serverInfo: MCP.Implementation
    private let generator: String
    private let timeZone: TimeZone

    public init(reader: any MeetingReading, version: String, timeZone: TimeZone = .current) {
        self.reader = reader
        self.serverInfo = MCP.Implementation(name: "mini-whisper", version: version)
        self.generator = "Mini Whisper \(version)"
        self.timeZone = timeZone
    }

    /// Serves lines until `readLine` returns `nil` (EOF), then returns exit status 0. `write`
    /// receives each reply as one JSON object and its newline; the caller flushes it.
    public func run(readLine: () -> String?, write: (String) -> Void) -> Int32 {
        while let line = readLine() {
            if let reply = handle(line: line) { write(reply + "\n") }
        }
        return 0
    }

    /// The reply to one line, without a newline; `nil` for a notification or a blank line.
    public func handle(line: String) -> String? {
        guard !line.allSatisfy(\.isWhitespace) else { return nil }
        let data = Data(line.utf8)
        let header: MCP.Header
        do {
            header = try JSONDecoder().decode(MCP.Header.self, from: data)
        } catch DecodingError.dataCorrupted(let context) where context.codingPath.isEmpty {
            return failure(nil, .parse)
        } catch {
            return failure(nil, .invalidRequest)
        }

        guard case .valid(let id) = header.id else {
            // A notification gets no reply, even when it fails.
            if case .absent = header.id, header.method != nil { return nil }
            return failure(nil, .invalidRequest)
        }
        guard header.jsonrpc == "2.0", let method = header.method else { return failure(id, .invalidRequest) }

        let stateless: Bool
        switch era(of: data) {
        case .success(let isStateless): stateless = isStateless
        case .failure(let error): return failure(id, error)
        }
        switch method {
        case "initialize":
            Log.meeting.info("mcp: initialize")
            return initialize(id, data, stateless: stateless)
        case "ping":
            Log.meeting.info("mcp: ping")
            return reply(id, MCP.Empty(), stateless: stateless)
        case "server/discover":
            Log.meeting.info("mcp: server/discover")
            // Only the stateless revision defines it, so its result always takes that shape.
            let result = MCP.DiscoverResult(supportedVersions: Self.supportedVersions)
            return reply(id, result, stateless: true, cacheable: true)
        case "tools/list":
            Log.meeting.info("mcp: tools/list")
            let result = MCP.ToolList(tools: Tool.allCases.map(\.definition))
            return reply(id, result, stateless: stateless, cacheable: true)
        case "tools/call":
            return call(id, data, stateless: stateless)
        default:
            Log.meeting.info("mcp: unknown method")
            return failure(id, .methodNotFound)
        }
    }

    // MARK: Protocol

    /// Whether the request is stateless: it carries a `_meta` protocol version, which must be
    /// 2026-07-28. Requests without one follow the `initialize` handshake.
    private func era(of data: Data) -> Result<Bool, RPCError> {
        let meta: MCP.MetaParams.Meta?
        do {
            meta = try JSONDecoder().decode(MCP.Request<MCP.MetaParams>.self, from: data).params?.meta
        } catch {
            return .failure(.malformed(error))
        }
        guard let version = meta?.protocolVersion?.value else { return .success(false) }
        guard version == Self.statelessVersion else { return .failure(.unsupportedVersion(version)) }
        guard meta?.clientCapabilities != nil else {
            return .failure(.invalidParams("Invalid params: io.modelcontextprotocol/clientCapabilities is required"))
        }
        return .success(true)
    }

    private func initialize(_ id: MCP.RequestID, _ data: Data, stateless: Bool) -> String {
        let requested: String
        do {
            guard let params = try JSONDecoder().decode(MCP.Request<MCP.InitializeParams>.self, from: data).params
            else { return failure(id, .invalidParams("Invalid params: protocolVersion is required")) }
            requested = params.protocolVersion.value
        } catch {
            return failure(id, .malformed(error))
        }
        // Planning decision 30: an unsupported version is answered with the newest one.
        let version = Self.handshakeVersions.contains(requested) ? requested : Self.handshakeVersions[0]
        return reply(id, MCP.InitializeResult(protocolVersion: version, serverInfo: serverInfo), stateless: stateless)
    }

    private func reply(
        _ id: MCP.RequestID, _ body: some Encodable, stateless: Bool, cacheable: Bool = false
    ) -> String {
        guard stateless else { return encoded(MCP.Response(id: id, result: body)) }
        let result = MCP.Stateless(body: body, serverInfo: serverInfo, cacheable: cacheable)
        return encoded(MCP.Response(id: id, result: result))
    }

    private func failure(_ id: MCP.RequestID?, _ error: RPCError) -> String {
        encoded(MCP.ErrorResponse(id: id, error: error.body))
    }

    /// One line: JSON escapes `\n` and `\r`, and the Unicode line breaks it leaves raw are
    /// escaped too, so no reader splits a reply.
    private func encoded(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            return #"{"error":{"code":-32603,"message":"Internal error"},"jsonrpc":"2.0"}"#
        }
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{85}", with: "\\u0085")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    // MARK: Tools

    private func call(_ id: MCP.RequestID, _ data: Data, stateless: Bool) -> String {
        let name: String
        do {
            guard let params = try JSONDecoder().decode(MCP.Request<MCP.CallParams>.self, from: data).params
            else { return failure(id, .invalidParams("Invalid params: name is required")) }
            name = params.name.value
        } catch {
            return failure(id, .malformed(error))
        }
        guard let tool = Tool(rawValue: name) else {
            Log.meeting.info("mcp: tools/call unknown tool")
            return failure(id, .invalidParams("Unknown tool: \(name)"))
        }
        // The tool name only: ids and search text stay out of the log.
        Log.meeting.info("mcp: tools/call \(tool.rawValue)")

        let outcome: Result<String, ToolError>
        do {
            switch tool {
            case .listMeetings:
                outcome = index().flatMap { json($0) }
            case .getTranscript:
                outcome = transcript(try arguments(MCP.IDArguments.self, in: data).id.value)
            case .getSummary:
                outcome = summary(try arguments(MCP.IDArguments.self, in: data).id.value)
            case .searchMeetings:
                let arguments = try arguments(MCP.SearchArguments.self, in: data)
                outcome = search(arguments.query.value, limit: arguments.limit)
            }
        } catch let error as MCP.OverlongString {
            return failure(id, .malformed(error))
        } catch {
            outcome = .failure(ToolError("invalid arguments for \(tool.rawValue); see its inputSchema"))
        }

        let result = switch outcome {
        case .success(let text): MCP.ToolResult(content: [.init(text: text)], isError: false)
        case .failure(let error): MCP.ToolResult(content: [.init(text: error.text)], isError: true)
        }
        return reply(id, result, stateless: stateless)
    }

    private func arguments<Arguments: Decodable>(
        _ type: Arguments.Type, in data: Data
    ) throws -> Arguments {
        let request = try JSONDecoder().decode(MCP.Request<MCP.CallArguments<Arguments>>.self, from: data)
        guard let arguments = request.params?.arguments else { throw ToolError("missing arguments") }
        return arguments
    }

    private func transcript(_ id: String) -> Result<String, ToolError> {
        meeting(id).map { MeetingMarkdown.transcript($0, generator: generator, timeZone: timeZone) }
    }

    private func summary(_ id: String) -> Result<String, ToolError> {
        meeting(id).flatMap { loaded in
            Result { try MeetingMarkdown.summary(loaded, generator: generator, timeZone: timeZone) }
                .mapError { _ in ToolError("no summary for meeting \(id)") }
        }
    }

    private func search(_ query: String, limit: Int?) -> Result<String, ToolError> {
        let limit = min(max(limit ?? Self.searchLimit, 1), Self.searchLimit)
        return index().flatMap { entries in
            // An unreadable meeting is skipped, as the CLI's search skips it.
            let hits = MeetingSearch().search(query, in: entries.compactMap { try? reader.load($0.id) })
            return json(Array(hits.prefix(limit)))
        }
    }

    private func meeting(_ text: String) -> Result<LoadedMeeting, ToolError> {
        MeetingID.resolve(text, in: reader)
            .mapError { ToolError($0.localizedDescription) }
            .flatMap { id in
                Result { try reader.load(id) }
                    .mapError { ToolError("could not read meeting \(text): \($0.localizedDescription)") }
            }
    }

    private func index() -> Result<[IndexEntry], ToolError> {
        Result { try reader.index() }
            .mapError { ToolError(MeetingIDError.unreadable($0.localizedDescription).localizedDescription) }
    }

    private func json(_ value: some Encodable) -> Result<String, ToolError> {
        Result { String(decoding: try MeetingCoding.encoder().encode(value), as: UTF8.self) }
            .mapError { ToolError("could not encode JSON: \($0.localizedDescription)") }
    }
}

/// A tool's failure, reported to the model as an `isError` result.
private struct ToolError: Error {
    let text: String

    init(_ text: String) {
        self.text = text
    }
}

private enum RPCError: Error {
    case parse
    case invalidRequest
    case methodNotFound
    /// The whole message.
    case invalidParams(String)
    case unsupportedVersion(String)

    /// A decoding failure of `params`.
    static func malformed(_ error: any Error) -> RPCError {
        error is MCP.OverlongString
            ? .invalidParams("Invalid params: strings are limited to \(MCP.maximumStringLength) characters")
            : .invalidParams("Invalid params")
    }

    var body: MCP.ErrorResponse.Body {
        switch self {
        case .parse:
            .init(code: -32700, message: "Parse error", data: nil)
        case .invalidRequest:
            .init(code: -32600, message: "Invalid Request", data: nil)
        case .methodNotFound:
            .init(code: -32601, message: "Method not found", data: nil)
        case .invalidParams(let message):
            .init(code: -32602, message: message, data: nil)
        case .unsupportedVersion(let requested):
            .init(
                code: -32022, message: "Unsupported protocol version",
                data: MCP.VersionMismatch(supported: MCPServer.supportedVersions, requested: requested)
            )
        }
    }
}

/// The four read-only tools (design §5.3).
private enum Tool: String, CaseIterable {
    case listMeetings = "list_meetings"
    case getTranscript = "get_transcript"
    case getSummary = "get_summary"
    case searchMeetings = "search_meetings"

    private static let id = MCP.Property(
        type: "string", description: "The meeting's UUID, or at least its first 8 hex characters.",
        maxLength: MCP.maximumStringLength
    )

    var definition: MCP.Tool {
        switch self {
        case .listMeetings:
            MCP.Tool(
                name: rawValue, title: "List meetings",
                description: "Lists recorded meetings, newest first, as a JSON array: id, title, start and end, "
                    + "duration in seconds, speaker count, whether a summary exists, and an excerpt.",
                inputSchema: MCP.Schema(properties: [:], required: nil)
            )
        case .getTranscript:
            MCP.Tool(
                name: rawValue, title: "Get transcript",
                description: "Returns a meeting's transcript as Markdown: timed speaker paragraphs, notes, "
                    + "and gap and pause markers.",
                inputSchema: MCP.Schema(properties: ["id": Self.id], required: ["id"])
            )
        case .getSummary:
            MCP.Tool(
                name: rawValue, title: "Get summary",
                description: "Returns a meeting's summary as Markdown; an error when it has none.",
                inputSchema: MCP.Schema(properties: ["id": Self.id], required: ["id"])
            )
        case .searchMeetings:
            MCP.Tool(
                name: rawValue, title: "Search meetings",
                description: "Finds text, ignoring case, in meeting titles, transcripts, notes and summaries. "
                    + "Returns a JSON array with one hit per meeting, newest first, each with up to two snippets.",
                inputSchema: MCP.Schema(
                    properties: [
                        "query": MCP.Property(
                            type: "string", description: "The text to find.", maxLength: MCP.maximumStringLength
                        ),
                        "limit": MCP.Property(
                            type: "integer", description: "The most meetings to return; default 50.",
                            minimum: 1, maximum: 50
                        ),
                    ],
                    required: ["query"]
                )
            )
        }
    }
}
