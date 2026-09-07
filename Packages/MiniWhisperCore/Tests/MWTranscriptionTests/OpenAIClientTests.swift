import Foundation
import MWSupport
import MWTestSupport
import Testing

@testable import MWTranscription

/// One part of a `multipart/form-data` body.
private struct MultipartPart: Equatable {
    var name: String
    var filename: String?
    var contentType: String?
    var body: String
}

private enum MultipartError: Error { case notMultipart }

/// Reads a request's multipart body back out, so the wire shape can be asserted
/// field by field (design §5.4 OpenAI HTTP).
private func multipartParts(of request: URLRequest) throws -> [MultipartPart] {
    guard let header = request.value(forHTTPHeaderField: "Content-Type"),
        let boundary = header.components(separatedBy: "boundary=").last, !boundary.isEmpty
    else { throw MultipartError.notMultipart }
    let text = String(decoding: request.httpBody ?? Data(), as: UTF8.self)

    return text.components(separatedBy: "--\(boundary)").compactMap { chunk in
        // CRLF is a single Swift Character, so trim the sequence rather than counting.
        let section = String(chunk.trimmingPrefix("\r\n"))
        guard let separator = section.range(of: "\r\n\r\n") else { return nil }
        let headers = section[..<separator.lowerBound].components(separatedBy: "\r\n")
        var body = String(section[separator.upperBound...])
        if body.hasSuffix("\r\n") { body.removeLast("\r\n".count) }

        func attribute(_ name: String, in line: String) -> String? {
            line.components(separatedBy: "\(name)=\"").dropFirst().first?.components(separatedBy: "\"").first
        }
        let disposition = headers.first { $0.hasPrefix("Content-Disposition:") } ?? ""
        guard let field = attribute("name", in: disposition) else { return nil }
        let type = headers.first { $0.hasPrefix("Content-Type:") }?
            .components(separatedBy: ": ").last

        return MultipartPart(
            name: field,
            filename: attribute("filename", in: disposition),
            contentType: type,
            body: body
        )
    }
}

private func json(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// Batch transcription and cleanup over the `HTTPTransport` seam, ported from
/// `../mini-whisper-py/tests/test_transcriber.py` and `test_cleaner.py` with the request
/// shapes of design §5.4 asserted field by field.
@Suite struct OpenAIClientTests {
    private static let key = "sk-test-not-a-real-key"
    private static let wav = Data("RIFF....fake wav data".utf8)

    private func client(_ transport: FakeHTTPTransport) -> OpenAIClient {
        OpenAIClient(apiKey: Self.key, transport: transport)
    }

    private func stubbed(_ json: String, status: Int = 200) -> FakeHTTPTransport {
        FakeHTTPTransport(stubs: [HTTPStub(status: status, json: json)])
    }

    // MARK: - Transcription

    @Test func transcribeBuildsMultipartWithFileModelAndFormat() async throws {
        let transport = stubbed(#"{"text": "hello world"}"#)

        _ = try await client(transport).transcribe(wav: Self.wav, prompt: "")

        let request = try #require(transport.calls.first).request
        #expect(request.url == URL(string: "https://api.openai.com/v1/audio/transcriptions"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.key)")
        let parts = try multipartParts(of: request)
        #expect(parts.map(\.name) == ["file", "model", "response_format"])
        #expect(parts.first == MultipartPart(
            name: "file",
            filename: "audio.wav",
            contentType: "audio/wav",
            body: "RIFF....fake wav data"
        ))
        #expect(parts.dropFirst().map(\.body) == ["gpt-4o-mini-transcribe", "json"])
    }

    @Test func transcribeIncludesPromptWhenNonEmpty() async throws {
        let transport = stubbed(#"{"text": "hi"}"#)

        _ = try await client(transport).transcribe(wav: Self.wav, prompt: "Be precise.")

        let parts = try multipartParts(of: try #require(transport.calls.first).request)
        #expect(parts.map(\.name) == ["file", "model", "response_format", "prompt"])
        #expect(parts.last?.body == "Be precise.")
    }

    @Test func transcribeOmitsPromptWhenEmpty() async throws {
        let transport = stubbed(#"{"text": "hi"}"#)

        _ = try await client(transport).transcribe(wav: Self.wav, prompt: "")

        let parts = try multipartParts(of: try #require(transport.calls.first).request)
        #expect(!parts.map(\.name).contains("prompt"))
        #expect(!parts.map(\.name).contains("instructions"))
    }

    @Test func transcribeParsesTextAndUsage() async throws {
        let transport = stubbed(#"{"text": "hello world", "usage": {"input_tokens": 42, "output_tokens": 7}}"#)

        let (text, usage) = try await client(transport).transcribe(wav: Self.wav, prompt: "")

        #expect(text == "hello world")
        #expect(usage == TokenUsage(inputTokens: 42, outputTokens: 7))
    }

    @Test func transcribeMissingUsageIsZero() async throws {
        let transport = stubbed(#"{"text": "hello"}"#)

        let (text, usage) = try await client(transport).transcribe(wav: Self.wav, prompt: "")

        #expect(text == "hello")
        #expect(usage == TokenUsage())
    }

    @Test func transcribeEmptyWavThrows() async {
        let transport = stubbed(#"{"text": "hi"}"#)

        let thrown = await #expect(throws: APIError.self) {
            try await client(transport).transcribe(wav: Data(), prompt: "")
        }

        #expect(thrown?.userMessage == "Audio buffer is empty")
        #expect(transport.calls.isEmpty)
    }

    @Test func transcribeTimeoutIs30s() async throws {
        let transport = stubbed(#"{"text": "hi"}"#)

        _ = try await client(transport).transcribe(wav: Self.wav, prompt: "")

        #expect(try #require(transport.calls.first).timeout == .seconds(30))
    }

    // MARK: - Cleanup

    @Test func cleanSendsSystemPromptAndUserText() async throws {
        let transport = stubbed(#"{"choices": [{"message": {"content": "ok"}}]}"#)

        _ = try await client(transport).clean("raw", prompt: "My system prompt.")

        let request = try #require(transport.calls.first).request
        #expect(request.url == URL(string: "https://api.openai.com/v1/chat/completions"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.key)")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try json(try #require(request.httpBody))
        #expect(body["model"] as? String == "gpt-4o-mini")
        #expect(body["temperature"] as? Double == 0.3)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [
            ["role": "system", "content": "My system prompt."],
            ["role": "user", "content": "raw"],
        ])
    }

    @Test func cleanTrimsContent() async throws {
        let transport = stubbed(#"{"choices": [{"message": {"content": "  trimmed  "}}]}"#)

        let (text, _) = try await client(transport).clean("input", prompt: "prompt")

        #expect(text == "trimmed")
    }

    @Test func cleanUsesPromptAndCompletionTokens() async throws {
        let transport = stubbed("""
            {"choices": [{"message": {"content": "ok"}}],
             "usage": {"prompt_tokens": 10, "completion_tokens": 5, "input_tokens": 99}}
            """)

        let (_, usage) = try await client(transport).clean("input", prompt: "prompt")

        #expect(usage == TokenUsage(inputTokens: 10, outputTokens: 5))
    }

    @Test func cleanMissingUsageIsZero() async throws {
        let transport = stubbed(#"{"choices": [{"message": {"content": "ok"}}]}"#)

        let (_, usage) = try await client(transport).clean("input", prompt: "prompt")

        #expect(usage == TokenUsage())
    }

    @Test func cleanTimeoutIs15s() async throws {
        let transport = stubbed(#"{"choices": [{"message": {"content": "ok"}}]}"#)

        _ = try await client(transport).clean("input", prompt: "prompt")

        #expect(try #require(transport.calls.first).timeout == .seconds(15))
    }

    // MARK: - Transport

    /// No cookie or cache persistence for the vendor calls (design §5.8).
    @Test func sessionIsEphemeral() {
        let configuration = URLSessionTransport().session.configuration

        #expect(configuration.urlCache?.diskCapacity == 0)
        #expect(configuration.httpCookieStorage !== HTTPCookieStorage.shared)
    }

    /// F3: the key never reaches a log, on the success or the failure path.
    @Test func authorizationHeaderNotLogged() async throws {
        let sink = CapturingLogSink()

        await Log.withSinks(debug: true, sinks: [sink]) {
            let failing = stubbed(#"{"error": "nope"}"#, status: 401)
            _ = try? await client(failing).transcribe(wav: Self.wav, prompt: "")
            let succeeding = stubbed(#"{"choices": [{"message": {"content": "ok"}}]}"#)
            _ = try? await client(succeeding).clean("input", prompt: "prompt")
        }

        #expect(!sink.lines.isEmpty)
        for line in sink.lines {
            #expect(!line.contains(Self.key))
            #expect(!line.contains("Bearer"))
            #expect(!line.contains("Authorization"))
        }
    }
}
