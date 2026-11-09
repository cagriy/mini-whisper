import Foundation
import MWSupport

/// One summary request: the system prompt and the delimited meeting data in, the text out.
public protocol Summarizing: Sendable {
    func summarise(system: String, user: String) async throws -> SummaryResult
}

/// `refusalCategory` is set only when the model declined (`stop_reason: "refusal"`).
public struct SummaryResult: Sendable, Equatable {
    public var text: String
    public var usage: TokenUsage
    public var refusalCategory: String?

    public init(text: String, usage: TokenUsage = TokenUsage(), refusalCategory: String? = nil) {
        self.text = text
        self.usage = usage
        self.refusalCategory = refusalCategory
    }
}

/// The meeting summary call pinned to design §5.3: one Messages API request at low effort
/// with server-side refusal fallbacks, 180 s, no automatic retry.
public struct AnthropicClient: Summarizing {
    public static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2026-10-21"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    public static let model = "claude-sonnet-5-5"
    public static let maxTokens = 16000
    public static let effort = "low"
    public static let timeout = Duration.seconds(180)

    private let apiKey: String
    private let transport: any HTTPTransport
    private let log = Log.meeting

    public init(apiKey: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    public func summarise(system: String, user: String) async throws -> SummaryResult {
        // No temperature/top_p/top_k: API version 2026-10-21 rejects them.
        let body = try JSONSerialization.data(withJSONObject: [
            "model": Self.model,
            "max_tokens": Self.maxTokens,
            "output_config": ["effort": Self.effort],
            "fallbacks": "default",
            "system": system,
            "messages": [["role": "user", "content": user]],
        ] as [String: Any])

        var request = URLRequest(url: Self.messagesURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body

        // Log lines carry sizes, status and token counts only (R27).
        let sent = "summary request \(body.count) bytes"
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request, timeout: Self.timeout)
        } catch {
            log.info("\(sent) failed: \(AnyError(error).description)")
            throw APIError.transport(error)
        }
        guard (200..<300).contains(response.statusCode) else {
            log.info("\(sent), HTTP \(response.statusCode)")
            throw APIError.httpStatus(response.statusCode)
        }
        let reply: MessagesResponse
        do {
            reply = try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            log.info("\(sent), HTTP \(response.statusCode), reply could not be decoded")
            throw APIError.transport(error)
        }

        let usage = TokenUsage(
            inputTokens: reply.usage?.inputTokens ?? 0,
            outputTokens: reply.usage?.outputTokens ?? 0
        )
        log.info("\(sent), HTTP \(response.statusCode), \(usage.inputTokens) input / \(usage.outputTokens) output tokens")
        return SummaryResult(
            text: reply.content.filter { $0.type == "text" }.compactMap(\.text).joined(),
            usage: usage,
            // The category may be null; a refusal must still read as one.
            refusalCategory: reply.stopReason == "refusal"
                ? (reply.stopDetails?.category ?? "unspecified") : nil
        )
    }
}

// MARK: - Wire shapes

private struct MessagesResponse: Decodable {
    struct Block: Decodable {
        var type: String
        var text: String?
    }

    struct StopDetails: Decodable {
        var category: String?
    }

    struct Usage: Decodable {
        var inputTokens: Int?
        var outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    var content: [Block]
    var stopReason: String?
    var stopDetails: StopDetails?
    var usage: Usage?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
        case stopDetails = "stop_details"
        case usage
    }
}
