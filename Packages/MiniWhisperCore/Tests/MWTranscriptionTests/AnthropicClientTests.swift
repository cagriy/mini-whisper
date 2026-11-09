import Foundation
import MWSupport
import MWTestSupport
import Testing

import MWTranscription

private func body(of transport: FakeHTTPTransport) throws -> Data {
    let call = try #require(transport.calls.first)
    return try #require(call.request.httpBody)
}

private func json(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// The summary request of design §5.3 over the `HTTPTransport` seam: headers, body, the
/// 180 s timeout, text-block joining, the refusal category and `APIError` mapping.
@Suite struct AnthropicClientTests {
    private static let key = "placeholder-not-a-real-key"
    private static let reply = #"""
        {"content": [{"type": "text", "text": "## Summary"}], "stop_reason": "end_turn",
         "usage": {"input_tokens": 1, "output_tokens": 1}}
        """#

    private func summarise(
        _ transport: FakeHTTPTransport,
        system: String = "Summarise.",
        user: String = "Speakers: Ada"
    ) async throws -> SummaryResult {
        try await AnthropicClient(apiKey: Self.key, transport: transport)
            .summarise(system: system, user: user)
    }

    private func stubbed(_ json: String = reply, status: Int = 200) -> FakeHTTPTransport {
        FakeHTTPTransport(stubs: [HTTPStub(status: status, json: json)])
    }

    @Test func postsToMessagesWithHeaders() async throws {
        let transport = stubbed()

        _ = try await summarise(transport)

        let request = try #require(transport.calls.first).request
        #expect(request.url == URL(string: "https://api.anthropic.com/v1/messages"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == Self.key)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func bodyCarriesModelMaxTokensEffortAndFallbacks() async throws {
        let transport = stubbed()

        _ = try await summarise(transport, system: "The prompt file.", user: "<transcript>…</transcript>")

        let body = try json(try body(of: transport))
        #expect(body["model"] as? String == "claude-sonnet-5-5")
        #expect(body["max_tokens"] as? Int == 16000)
        #expect(body["output_config"] as? [String: String] == ["effort": "low"])
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["system"] as? String == "The prompt file.")
        #expect(body["messages"] as? [[String: String]] == [
            ["role": "user", "content": "<transcript>…</transcript>"],
        ])
        #expect(Set(body.keys) == ["model", "max_tokens", "output_config", "fallbacks", "system", "messages"])
    }

    @Test func timeoutIs180Seconds() async throws {
        let transport = stubbed()

        _ = try await summarise(transport)

        #expect(try #require(transport.calls.first).timeout == .seconds(180))
    }

    @Test func joinsTextBlocksAndReadsUsage() async throws {
        let transport = stubbed(#"""
            {"content": [
                {"type": "thinking", "thinking": "", "signature": "sig"},
                {"type": "text", "text": "## Summary\n"},
                {"type": "text", "text": "Shipped."}
             ],
             "stop_reason": "end_turn", "stop_details": null,
             "usage": {"input_tokens": 1200, "output_tokens": 340, "cache_read_input_tokens": 0}}
            """#)

        let result = try await summarise(transport)

        #expect(result == SummaryResult(
            text: "## Summary\nShipped.",
            usage: TokenUsage(inputTokens: 1200, outputTokens: 340),
            refusalCategory: nil
        ))
    }

    @Test func refusalCarriesTheCategory() async throws {
        let transport = stubbed(#"""
            {"content": [], "stop_reason": "refusal",
             "stop_details": {"type": "refusal", "category": "cyber", "explanation": "…"},
             "usage": {"input_tokens": 900, "output_tokens": 3}}
            """#)

        let result = try await summarise(transport)

        #expect(result.refusalCategory == "cyber")
        #expect(result.text.isEmpty)
        #expect(result.usage == TokenUsage(inputTokens: 900, outputTokens: 3))
    }

    /// `stop_details.category` may be `null`; the refusal must still read as one.
    @Test func refusalWithoutACategoryIsStillARefusal() async throws {
        let transport = stubbed(#"""
            {"content": [], "stop_reason": "refusal",
             "stop_details": {"type": "refusal", "category": null},
             "usage": {"input_tokens": 900, "output_tokens": 0}}
            """#)

        let result = try await summarise(transport)

        #expect(result.refusalCategory == "unspecified")
    }

    @Test(arguments: [400, 401, 429, 500, 529])
    func non2xxMapsToHTTPStatus(_ status: Int) async throws {
        let transport = stubbed(#"{"type": "error", "error": {"type": "x", "message": "y"}}"#, status: status)

        let thrown = await #expect(throws: APIError.self) { try await summarise(transport) }

        guard case .httpStatus(let code) = thrown else {
            Issue.record("expected .httpStatus, got \(String(describing: thrown))")
            return
        }
        #expect(code == status)
    }

    @Test func transportFailureMapsToTransport() async throws {
        let transport = FakeHTTPTransport(failure: URLError(.timedOut))

        let thrown = await #expect(throws: APIError.self) { try await summarise(transport) }

        guard case .transport(let underlying) = thrown else {
            Issue.record("expected .transport, got \(String(describing: thrown))")
            return
        }
        #expect((underlying as? URLError)?.code == .timedOut)
    }

    @Test func undecodableReplyMapsToTransport() async throws {
        let transport = stubbed("not json")

        let thrown = await #expect(throws: APIError.self) { try await summarise(transport) }

        guard case .transport = thrown else {
            Issue.record("expected .transport, got \(String(describing: thrown))")
            return
        }
    }

    /// R27: sizes, status and token counts only — never the key, the prompt, the
    /// transcript or the summary.
    @Test func logsSizesAndStatusOnly() async throws {
        let sink = CapturingLogSink()
        let system = "SYSTEM-PROMPT-BODY"
        let user = "TRANSCRIPT-BODY Ada: ship it"
        let transport = stubbed(#"""
            {"content": [{"type": "text", "text": "SUMMARY-BODY"}], "stop_reason": "end_turn",
             "usage": {"input_tokens": 1200, "output_tokens": 340}}
            """#)

        await Log.withSinks(debug: true, sinks: [sink]) {
            _ = try? await summarise(transport, system: system, user: user)
            _ = try? await summarise(stubbed("{}", status: 500), system: system, user: user)
            _ = try? await summarise(FakeHTTPTransport(failure: URLError(.timedOut)), system: system, user: user)
        }

        let bytes = try body(of: transport).count
        #expect(sink.lines.count == 3)
        for line in sink.lines {
            for secret in [Self.key, system, user, "SUMMARY-BODY", "Ada"] {
                #expect(!line.contains(secret))
            }
            #expect(line.contains("meeting"))
        }
        #expect(sink.lines.filter { $0.contains("\(bytes) bytes") && $0.contains("HTTP 200") }.count == 1)
        #expect(sink.lines.contains { $0.contains("1200 input") && $0.contains("340 output") })
        #expect(sink.lines.contains { $0.contains("\(bytes) bytes") && $0.contains("HTTP 500") })
    }
}
