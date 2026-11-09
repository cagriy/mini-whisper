import Foundation
import MWConfig
import MWStreaming

/// The smallest adapter that exercises `WebSocketEngine`'s skeleton: a JSON open and
/// end message, binary audio chunks, and seven server event types.
public struct TestAdapter: EngineAdapter {
    public enum ServerError: Error, CustomStringConvertible {
        case reported(String)

        public var description: String {
            switch self {
            case .reported(let message): message
            }
        }
    }

    public let name: EngineName
    public let url = URL(string: "wss://example.invalid/stream")!
    public let headers: [String: String]
    public let targetRate: Double
    public let drainAfterComplete: Duration
    public let minimumChunkSeconds: Double?

    public init(
        name: EngineName = .openai,
        targetRate: Double = 16000,
        drainAfterComplete: Duration = .zero,
        minimumChunkSeconds: Double? = nil,
        headers: [String: String] = ["Authorization": "Bearer placeholder-not-a-real-key"]
    ) {
        self.name = name
        self.targetRate = targetRate
        self.drainAfterComplete = drainAfterComplete
        self.minimumChunkSeconds = minimumChunkSeconds
        self.headers = headers
    }

    public func openMessages() -> [WebSocketMessage] { [.text(#"{"type":"open"}"#)] }

    public func encodeChunk(_ pcm: Data) -> WebSocketMessage { .binary(pcm) }

    public func endMessages() -> [WebSocketMessage] { [.text(#"{"type":"end"}"#)] }

    public func handle(_ message: WebSocketMessage, emit: inout AdapterEmitter) throws -> Bool {
        guard case .text(let json) = message,
              case .object(let event)? = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        else { return false }

        guard case .string(let type)? = event["type"] else { return false }
        let text: String = if case .string(let value)? = event["text"] { value } else { "" }

        switch type {
        case "partial":
            emit.partial(text)
        case "final":
            emit.final(text)
        case "segment":
            emit.segment(TranscriptSegment(text: text, speaker: Self.string(event["speaker"]), start: 0, end: 0))
        case "revision":
            emit.speakerRevision([
                SpeakerRevision(turnOrder: Self.integer(event["turn_order"]) ?? 0, speaker: Self.string(event["speaker"]) ?? ""),
            ])
        case "limit":
            if case .number(let seconds)? = event["expires_at"] {
                emit.sessionLimit(.expiresAt(Date(timeIntervalSince1970: seconds)))
            } else {
                emit.sessionLimit(.warning)
            }
        case "complete":
            emit.addTokens(input: Self.integer(event["input_tokens"]), output: Self.integer(event["output_tokens"]))
            return true
        case "error":
            throw ServerError.reported(text)
        default:
            break
        }
        return false
    }

    private static func string(_ value: JSONValue?) -> String? {
        guard case .string(let string)? = value else { return nil }
        return string
    }

    private static func integer(_ value: JSONValue?) -> Int? {
        guard case .number(let number)? = value else { return nil }
        return Int(number)
    }
}
