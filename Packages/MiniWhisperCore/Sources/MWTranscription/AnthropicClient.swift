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
    public static let namingModel = "claude-haiku-5-5"
    public static let namingEffort = "medium"
    public static let namingMaxTokens = 8000
    public static let namingTimeout = Duration.seconds(60)
    private static let namingMaxSuggestions = 50

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

        // Log lines carry sizes, status and token counts only (R27).
        let sent = "summary request \(body.count) bytes"
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(
                messagesRequest(body, beta: Self.fallbackBeta), timeout: Self.timeout
            )
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

        let usage = reply.tokenUsage
        log.info("\(sent), HTTP \(response.statusCode), \(usage.inputTokens) input / \(usage.outputTokens) output tokens")
        return SummaryResult(
            text: reply.text,
            usage: usage,
            // The category may be null; a refusal must still read as one.
            refusalCategory: reply.stopReason == "refusal"
                ? (reply.stopDetails?.category ?? "unspecified") : nil
        )
    }

    private func messagesRequest(_ body: Data, beta: String? = nil) -> URLRequest {
        var request = URLRequest(url: Self.messagesURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if let beta { request.setValue(beta, forHTTPHeaderField: "anthropic-beta") }
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
        return request
    }
}

/// The naming call: Haiku 5.5 at medium effort with schema-constrained output, a cache
/// breakpoint on the system prompt and on the last closed transcript block, 60 s, no
/// fallback and no retry.
extension AnthropicClient: NameSuggesting {
    public func suggestNames(_ request: NamingRequest) async throws -> NamingReply {
        let ephemeral = ["type": "ephemeral"]
        var content: [[String: Any]] = request.blocks.enumerated().map { index, text in
            index == request.cacheBlocks - 1
                ? ["type": "text", "text": text, "cache_control": ephemeral]
                : ["type": "text", "text": text]
        }
        content.append(["type": "text", "text": request.state])
        // No thinking/temperature: Haiku 5.5 thinks adaptively by default, and API version
        // 2026-10-21 rejects sampling parameters.
        let body = try JSONSerialization.data(withJSONObject: [
            "model": Self.namingModel,
            "max_tokens": Self.namingMaxTokens,
            "output_config": [
                "effort": Self.namingEffort,
                "format": ["type": "json_schema", "schema": try JSONSerialization.jsonObject(with: request.schema)],
            ] as [String: Any],
            "system": [["type": "text", "text": request.system, "cache_control": ephemeral]],
            "messages": [["role": "user", "content": content]],
        ] as [String: Any])

        // Log lines carry bytes, status and token counts only (R29).
        let sent = "naming request \(body.count) bytes"
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(messagesRequest(body), timeout: Self.namingTimeout)
        } catch {
            let code = error as NSError
            Log.naming.info("\(sent) failed: \(code.domain) \(code.code)")
            throw NamingError.transport(Self.transportReason(error))
        }
        let status = "\(sent), HTTP \(response.statusCode)"
        guard (200..<300).contains(response.statusCode) else {
            Log.naming.info(status)
            switch response.statusCode {
            case 401, 403: throw NamingError.unauthorized
            case 429: throw NamingError.rateLimited
            default: throw NamingError.server(response.statusCode)
            }
        }
        guard let reply = try? JSONDecoder().decode(MessagesResponse.self, from: data) else {
            Log.naming.info("\(status), reply could not be decoded")
            throw NamingError.malformed
        }

        let usage = reply.tokenUsage
        Log.naming.info("""
            \(status), stop \(reply.stopReason ?? "none"), \(usage.inputTokens) input / \
            \(usage.cacheReadTokens) cache-read / \(usage.cacheWriteTokens) cache-write / \
            \(usage.outputTokens) output tokens
            """)
        switch reply.stopReason {
        case "refusal": throw NamingFailure(error: .refused, usage: usage)
        case "max_tokens": throw NamingFailure(error: .truncated, usage: usage)
        default: break
        }
        guard let output = try? JSONDecoder().decode(NamingOutput.self, from: Data(reply.text.utf8)) else {
            Log.naming.info("\(status), suggestions could not be decoded")
            throw NamingFailure(error: .malformed, usage: usage)
        }
        return NamingReply(suggestions: Array(output.suggestions.prefix(Self.namingMaxSuggestions)), usage: usage)
    }

    private static func transportReason(_ error: any Error) -> String {
        switch (error as? URLError)?.code {
        case .notConnectedToInternet?, .networkConnectionLost?: "no internet connection"
        case .timedOut?: "Anthropic did not answer in time"
        default: AnyError(error).description
        }
    }
}

// MARK: - Wire shapes

private struct NamingOutput: Decodable {
    var suggestions: [RawSuggestion]
}

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
        var cacheReadTokens: Int?
        var cacheWriteTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadTokens = "cache_read_input_tokens"
            case cacheWriteTokens = "cache_creation_input_tokens"
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

    /// A reply may open with `thinking` blocks; only `text` blocks carry the answer.
    var text: String {
        content.filter { $0.type == "text" }.compactMap(\.text).joined()
    }

    var tokenUsage: TokenUsage {
        TokenUsage(
            inputTokens: usage?.inputTokens ?? 0,
            outputTokens: usage?.outputTokens ?? 0,
            cacheReadTokens: usage?.cacheReadTokens ?? 0,
            cacheWriteTokens: usage?.cacheWriteTokens ?? 0
        )
    }
}
