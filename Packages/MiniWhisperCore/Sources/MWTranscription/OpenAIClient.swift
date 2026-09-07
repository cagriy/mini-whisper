import Foundation
import MWSupport

public protocol Transcriber: Sendable {
    func transcribe(wav: Data, prompt: String) async throws -> (String, TokenUsage)
}

public protocol Cleaner: Sendable {
    func clean(_ text: String, prompt: String) async throws -> (String, TokenUsage)
}

/// The two batch OpenAI calls, pinned to design §5.4: multipart transcription with
/// `gpt-4o-mini-transcribe` (30 s) and chat cleanup with `gpt-4o-mini` at temperature
/// 0.3 (15 s). A port of `../mini-whisper-py/src/mini_whisper/{transcriber,cleaner}.py`.
public struct OpenAIClient: Transcriber, Cleaner {
    public static let transcriptionsURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    public static let chatURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    public static let transcribeModel = "gpt-4o-mini-transcribe"
    public static let cleanupModel = "gpt-4o-mini"
    public static let transcribeTimeout = Duration.seconds(30)
    public static let cleanupTimeout = Duration.seconds(15)

    private let apiKey: String
    private let transport: any HTTPTransport
    private let log = Log.pipeline

    public init(apiKey: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    public func transcribe(wav: Data, prompt: String) async throws -> (String, TokenUsage) {
        guard !wav.isEmpty else { throw APIError.emptyAudio }

        var form = Multipart()
        form.addFile(name: "file", filename: "audio.wav", contentType: "audio/wav", data: wav)
        form.addField(name: "model", value: Self.transcribeModel)
        form.addField(name: "response_format", value: "json")
        if !prompt.isEmpty { form.addField(name: "prompt", value: prompt) }

        var request = signed(URLRequest(url: Self.transcriptionsURL))
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finished()

        let response: TranscriptionResponse = try await send(
            request, timeout: Self.transcribeTimeout, call: "transcription"
        )
        return (
            response.text ?? "",
            TokenUsage(
                inputTokens: response.usage?.inputTokens ?? 0,
                outputTokens: response.usage?.outputTokens ?? 0
            )
        )
    }

    public func clean(_ text: String, prompt: String) async throws -> (String, TokenUsage) {
        var request = signed(URLRequest(url: Self.chatURL))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: Self.cleanupModel,
            messages: [
                ChatRequest.Message(role: "system", content: prompt),
                ChatRequest.Message(role: "user", content: text),
            ],
            temperature: 0.3
        ))

        let response: ChatResponse = try await send(
            request, timeout: Self.cleanupTimeout, call: "cleanup"
        )
        let content = response.choices.first?.message.content ?? ""
        return (
            content.trimmingCharacters(in: .whitespacesAndNewlines),
            TokenUsage(
                inputTokens: response.usage?.promptTokens ?? 0,
                outputTokens: response.usage?.completionTokens ?? 0
            )
        )
    }

    // MARK: - Transport

    private func signed(_ request: URLRequest) -> URLRequest {
        var request = request
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Sends, maps the status to `APIError` (F14) and decodes. Log lines carry the call
    /// and the status only — never the key, the audio or the text (design §5.8).
    private func send<Response: Decodable>(
        _ request: URLRequest,
        timeout: Duration,
        call: String
    ) async throws -> Response {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request, timeout: timeout)
        } catch {
            log.info("\(call) request failed: \(AnyError(error).description)")
            throw APIError.transport(error)
        }
        guard (200..<300).contains(response.statusCode) else {
            log.info("\(call) returned HTTP \(response.statusCode)")
            throw APIError.httpStatus(response.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            log.info("\(call) response could not be decoded")
            throw APIError.transport(error)
        }
    }
}

// MARK: - Wire shapes

private struct TranscriptionResponse: Decodable {
    struct Usage: Decodable {
        var inputTokens: Int?
        var outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    var text: String?
    var usage: Usage?
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var temperature: Double
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }

        var message: Message
    }

    struct Usage: Decodable {
        var promptTokens: Int?
        var completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }

    var choices: [Choice]
    var usage: Usage?
}
