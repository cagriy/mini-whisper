import Foundation
import MWSupport

/// One naming request over the meeting so far: the fixed system prompt, the transcript
/// blocks, and the state block last.
public protocol NameSuggesting: Sendable {
    func suggestNames(_ request: NamingRequest) async throws -> NamingReply
}

/// `cacheBlocks` counts the leading transcript blocks to cache; the breakpoint goes on the
/// last of them. `schema` is the JSON schema's bytes, so the request stays `Sendable`.
public struct NamingRequest: Sendable, Equatable {
    public var system: String
    public var blocks: [String]
    public var cacheBlocks: Int
    public var state: String
    public var schema: Data

    public init(system: String, blocks: [String], cacheBlocks: Int, state: String, schema: Data) {
        self.system = system
        self.blocks = blocks
        self.cacheBlocks = cacheBlocks
        self.state = state
        self.schema = schema
    }
}

/// One suggestion exactly as the model wrote it; nothing here is trusted until checked.
public struct RawSuggestion: Decodable, Sendable, Equatable {
    public var speaker: String
    public var name: String
    public var confidence: String
    public var kind: String
    public var turn: Int
    public var quote: String

    public init(speaker: String, name: String, confidence: String, kind: String, turn: Int, quote: String) {
        self.speaker = speaker
        self.name = name
        self.confidence = confidence
        self.kind = kind
        self.turn = turn
        self.quote = quote
    }
}

public struct NamingReply: Sendable, Equatable {
    public var suggestions: [RawSuggestion]
    public var usage: TokenUsage

    public init(suggestions: [RawSuggestion], usage: TokenUsage = TokenUsage()) {
        self.suggestions = suggestions
        self.usage = usage
    }
}

public enum NamingError: Error, Sendable, Equatable {
    case unauthorized
    case rateLimited
    case server(Int)
    case refused
    case truncated
    case malformed
    /// Carries its own user-facing reason.
    case transport(String)

    /// Completes "Name suggestions paused: …." and "Names not suggested: …."
    public var reason: String {
        switch self {
        case .unauthorized: "the Anthropic key was refused"
        case .rateLimited: "Anthropic is rate-limiting requests"
        case .server(let status): "Anthropic returned an error (HTTP \(status))"
        case .refused: "Anthropic declined the request"
        case .truncated: "the reply was cut short"
        case .malformed: "the reply could not be read"
        case .transport(let reason): reason
        }
    }
}
