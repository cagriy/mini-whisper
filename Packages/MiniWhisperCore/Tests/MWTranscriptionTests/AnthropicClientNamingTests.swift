import Foundation
import MWSupport
import MWTestSupport
import Testing

import MWTranscription

private func json(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// The naming request over the `HTTPTransport` seam: Haiku 5.5 with a JSON schema and two
/// cache breakpoints, the reply's suggestions and cache usage, and `NamingError` mapping.
@Suite struct AnthropicClientNamingTests {
    private static let key = "placeholder-not-a-real-key"
    private static let schema = Data(#"""
        {"type":"object","additionalProperties":false,"required":["suggestions"],
         "properties":{"suggestions":{"type":"array"}}}
        """#.utf8)
    private static let blocks = [
        "<transcript>\nT1 S1 [00:05]: Morning all.\n",
        "T2 S2 [05:10]: Shall we start?\n",
        "T3 S1 [10:02]: Yes.\n</transcript>",
    ]

    private static func request(
        system: String = "Name the speakers.",
        blocks: [String] = blocks,
        cacheBlocks: Int = 2,
        state: String = "<state>\nmode: remote\n</state>"
    ) -> NamingRequest {
        NamingRequest(system: system, blocks: blocks, cacheBlocks: cacheBlocks, state: state, schema: schema)
    }

    /// A reply opening with a `thinking` block, as Haiku 5.5's adaptive thinking may send.
    private static func reply(
        text: String = #"{"suggestions": []}"#,
        stopReason: String = "end_turn",
        usage: [String: Int] = ["input_tokens": 1, "output_tokens": 1]
    ) throws -> String {
        let object: [String: Any] = [
            "content": [
                ["type": "thinking", "thinking": "", "signature": "sig"],
                ["type": "text", "text": text],
            ],
            "stop_reason": stopReason,
            "stop_details": NSNull(),
            "usage": usage,
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private static func suggestion(_ name: String, turn: Int = 1) -> [String: Any] {
        [
            "speaker": "S1", "name": name, "confidence": "certain",
            "kind": "self_introduction", "turn": turn, "quote": "I'm \(name)",
        ]
    }

    private static func suggestionsText(_ items: [[String: Any]]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["suggestions": items]), as: UTF8.self)
    }

    private func stubbed(_ json: String, status: Int = 200) -> FakeHTTPTransport {
        FakeHTTPTransport(stubs: [HTTPStub(status: status, json: json)])
    }

    private func suggest(
        _ transport: FakeHTTPTransport,
        _ request: NamingRequest = request()
    ) async throws -> NamingReply {
        try await AnthropicClient(apiKey: Self.key, transport: transport).suggestNames(request)
    }

    private func sentBody(_ transport: FakeHTTPTransport) throws -> [String: Any] {
        let call = try #require(transport.calls.first)
        return try json(try #require(call.request.httpBody))
    }

    // MARK: - Request

    @Test func postsToMessagesWithoutABetaHeader() async throws {
        let transport = stubbed(try Self.reply())

        _ = try await suggest(transport)

        let request = try #require(transport.calls.first).request
        #expect(request.url == URL(string: "https://api.anthropic.com/v1/messages"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == Self.key)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
    }

    @Test func bodyCarriesHaikuEffortMaxTokensAndTheSchema() async throws {
        let transport = stubbed(try Self.reply())

        _ = try await suggest(transport)

        let body = try sentBody(transport)
        #expect(body["model"] as? String == "claude-haiku-5-5")
        #expect(body["max_tokens"] as? Int == 8000)
        let output = try #require(body["output_config"] as? [String: Any])
        #expect(Set(output.keys) == ["effort", "format"])
        #expect(output["effort"] as? String == "medium")
        let format = try #require(output["format"] as? [String: Any])
        #expect(Set(format.keys) == ["type", "schema"])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(JSONSerialization.jsonObject(with: Self.schema) as? NSDictionary)
        #expect(format["schema"] as? NSDictionary == schema)
        for absent in ["fallbacks", "temperature", "thinking"] {
            #expect(body[absent] == nil, "\(absent) must not be sent")
        }
        #expect(Set(body.keys) == ["model", "max_tokens", "output_config", "system", "messages"])
    }

    @Test func systemIsOneCachedTextBlock() async throws {
        let transport = stubbed(try Self.reply())

        _ = try await suggest(transport, Self.request(system: "The fixed naming prompt."))

        let system = try #require(try sentBody(transport)["system"] as? [[String: Any]])
        #expect(system.count == 1)
        #expect(system.first?["type"] as? String == "text")
        #expect(system.first?["text"] as? String == "The fixed naming prompt.")
        #expect(system.first?["cache_control"] as? [String: String] == ["type": "ephemeral"])
    }

    /// The breakpoint sits on the last closed block only; the state block is never cached.
    @Test(arguments: [0, 1, 2, 3])
    func userContentIsTheBlocksThenTheStateWithOneBreakpoint(cacheBlocks: Int) async throws {
        let transport = stubbed(try Self.reply())

        _ = try await suggest(transport, Self.request(cacheBlocks: cacheBlocks, state: "<state>STATE</state>"))

        let messages = try #require(try sentBody(transport)["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages.first?["role"] as? String == "user")
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == Array(repeating: "text", count: 4))
        #expect(content.map { $0["text"] as? String } == Self.blocks + ["<state>STATE</state>"])
        let cached = content.indices.filter { content[$0]["cache_control"] != nil }
        #expect(cached == (cacheBlocks == 0 ? [] : [cacheBlocks - 1]))
        for index in cached {
            #expect(content[index]["cache_control"] as? [String: String] == ["type": "ephemeral"])
        }
    }

    @Test func timeoutIs60Seconds() async throws {
        let transport = stubbed(try Self.reply())

        _ = try await suggest(transport)

        #expect(try #require(transport.calls.first).timeout == .seconds(60))
    }

    // MARK: - Reply

    @Test func decodesSuggestionsAfterAThinkingBlock() async throws {
        let text = try Self.suggestionsText([[
            "speaker": "S2", "name": "Kate Morgan", "confidence": "likely",
            "kind": "addressed", "turn": 4, "quote": "Kate, over to you",
        ]])
        let transport = stubbed(try Self.reply(text: text))

        let reply = try await suggest(transport)

        #expect(reply.suggestions == [RawSuggestion(
            speaker: "S2", name: "Kate Morgan", confidence: "likely",
            kind: "addressed", turn: 4, quote: "Kate, over to you"
        )])
    }

    @Test func readsAllFourUsageFields() async throws {
        let transport = stubbed(try Self.reply(usage: [
            "input_tokens": 1200, "output_tokens": 90,
            "cache_read_input_tokens": 30000, "cache_creation_input_tokens": 4000,
        ]))

        let reply = try await suggest(transport)

        #expect(reply.usage == TokenUsage(
            inputTokens: 1200, outputTokens: 90, cacheReadTokens: 30000, cacheWriteTokens: 4000
        ))
    }

    @Test func keepsTheFirst50Suggestions() async throws {
        let items = (1...60).map { Self.suggestion("Name\($0)", turn: $0) }
        let transport = stubbed(try Self.reply(text: try Self.suggestionsText(items)))

        let reply = try await suggest(transport)

        #expect(reply.suggestions.count == 50)
        #expect(reply.suggestions.first?.name == "Name1")
        #expect(reply.suggestions.last?.name == "Name50")
    }

    // MARK: - Errors

    @Test(arguments: zip(
        [401, 403, 429, 503, 400],
        [NamingError.unauthorized, .unauthorized, .rateLimited, .server(503), .server(400)]
    ))
    func httpStatusMaps(_ status: Int, _ expected: NamingError) async throws {
        let transport = stubbed(#"{"type": "error", "error": {"type": "x", "message": "y"}}"#, status: status)

        await #expect(throws: expected) { try await suggest(transport) }
    }

    /// A 200 reply that cannot be used still spent tokens, so the failure carries them.
    private static let spent: [String: Int] = [
        "input_tokens": 1200, "output_tokens": 8000,
        "cache_read_input_tokens": 300, "cache_creation_input_tokens": 40,
    ]
    private static let spentUsage = TokenUsage(
        inputTokens: 1200, outputTokens: 8000, cacheReadTokens: 300, cacheWriteTokens: 40
    )

    @Test func refusalIsRefusedWithItsUsage() async throws {
        let transport = stubbed(try Self.reply(text: "", stopReason: "refusal", usage: Self.spent))

        await #expect(throws: NamingFailure(error: .refused, usage: Self.spentUsage)) { try await suggest(transport) }
    }

    @Test func maxTokensStopIsTruncatedWithItsUsage() async throws {
        let text = #"{"suggestions": [{"speaker": "S1""#
        let transport = stubbed(try Self.reply(text: text, stopReason: "max_tokens", usage: Self.spent))

        await #expect(throws: NamingFailure(error: .truncated, usage: Self.spentUsage)) { try await suggest(transport) }
    }

    @Test(arguments: [
        "Kate is speaker one.",
        #"{"names": []}"#,
        #"{"suggestions": [{"speaker": "S1", "name": "Kate"}]}"#,
    ])
    func unusableTextIsMalformedWithItsUsage(_ text: String) async throws {
        let transport = stubbed(try Self.reply(text: text, usage: Self.spent))

        await #expect(throws: NamingFailure(error: .malformed, usage: Self.spentUsage)) { try await suggest(transport) }
    }

    /// No usage can be read from an envelope that does not decode.
    @Test func undecodableEnvelopeIsMalformed() async throws {
        let transport = stubbed("not json")

        await #expect(throws: NamingError.malformed) { try await suggest(transport) }
    }

    @Test(arguments: zip(
        [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut],
        ["no internet connection", "no internet connection", "Anthropic did not answer in time"]
    ))
    func transportFailureIsTransport(_ code: URLError.Code, _ reason: String) async throws {
        let transport = FakeHTTPTransport(failure: URLError(code))

        await #expect(throws: NamingError.transport(reason)) { try await suggest(transport) }
    }

    @Test func otherTransportFailuresKeepTheirDescription() async throws {
        let transport = FakeHTTPTransport(failure: URLError(.cannotFindHost))

        let thrown = await #expect(throws: NamingError.self) { try await suggest(transport) }

        #expect(thrown == .transport(AnyError(URLError(.cannotFindHost)).description))
    }

    @Test func eachErrorHasAShortReason() {
        #expect(NamingError.unauthorized.reason == "the Anthropic key was refused")
        #expect(NamingError.rateLimited.reason == "Anthropic is rate-limiting requests")
        #expect(NamingError.server(503).reason.contains("503"))
        #expect(NamingError.transport("no internet connection").reason == "no internet connection")
        let all: [NamingError] = [
            .unauthorized, .rateLimited, .server(500), .refused, .truncated, .malformed, .transport("x"),
        ]
        #expect(Set(all.map(\.reason)).count == all.count)
        for error in all {
            #expect(!error.reason.isEmpty)
            #expect(!error.reason.hasSuffix("."))
        }
    }

    // MARK: - Logs

    /// R29: bytes, status and token counts only — never the key, the prompt, the transcript,
    /// the state, a name or a quote.
    @Test func logsBytesStatusAndTokensOnly() async throws {
        let sink = CapturingLogSink()
        let request = Self.request(
            system: "SYSTEM-PROMPT-BODY",
            blocks: ["<transcript>TRANSCRIPT-BODY Hi, I'm Kate Morgan</transcript>"],
            cacheBlocks: 1,
            state: "<state>people: Priya Shah</state>"
        )
        let text = try Self.suggestionsText([Self.suggestion("Kate Morgan")])
        let transport = stubbed(try Self.reply(text: text, usage: [
            "input_tokens": 1200, "output_tokens": 90,
            "cache_read_input_tokens": 300, "cache_creation_input_tokens": 40,
        ]))

        try await Log.withSinks(debug: true, sinks: [sink]) {
            _ = try await suggest(transport, request)
            _ = try? await suggest(stubbed("{}", status: 500), request)
            _ = try? await suggest(stubbed(try Self.reply(text: "", stopReason: "refusal")), request)
            _ = try? await suggest(FakeHTTPTransport(failure: URLError(.timedOut)), request)
        }

        let sent = try #require(transport.calls.first)
        let bytes = try #require(sent.request.httpBody).count
        #expect(sink.records.count == 4)
        #expect(sink.records.allSatisfy { $0.category == "naming" })
        for line in sink.lines {
            for secret in [Self.key, "SYSTEM-PROMPT-BODY", "TRANSCRIPT-BODY", "Kate", "Morgan", "Priya", "I'm"] {
                #expect(!line.contains(secret), "\(line) leaks \(secret)")
            }
        }
        #expect(sink.lines.contains {
            $0.contains("\(bytes) bytes") && $0.contains("HTTP 200") && $0.contains("1200 input")
                && $0.contains("300 cache-read") && $0.contains("40 cache-write") && $0.contains("90 output")
        })
        #expect(sink.lines.contains { $0.contains("\(bytes) bytes") && $0.contains("HTTP 500") })
        #expect(sink.lines.contains { $0.contains("HTTP 200") && $0.contains("refusal") })
    }
}
