import Foundation
import MWConfig

/// OpenAI Realtime transcription session, pinned to design §5.4.
public struct OpenAIRealtimeAdapter: EngineAdapter {
    private static let model = "gpt-live-transcribe"

    public let name = EngineName.openai
    public let url = URL(string: "wss://api.openai.com/v1/realtime")!
    public let headers: [String: String]
    public let targetRate: Double = 24000
    /// Server VAD can complete a mid-stream segment concurrently with our commit, so
    /// the post-commit segment is scooped up rather than dropped.
    public let drainAfterComplete = Duration.milliseconds(200)

    /// Deltas accumulate per segment; the partial is always the whole segment.
    private var deltas = ""

    public init(apiKey: String) {
        headers = ["Authorization": "Bearer \(apiKey)"]
    }

    public func openMessages() -> [WebSocketMessage] {
        [AdapterJSON.text([
            "type": .string("session.update"),
            "session": .object([
                "type": .string("transcription"),
                "audio": .object([
                    "input": .object([
                        "format": .object(["type": .string("audio/pcm"), "rate": .number(targetRate)]),
                        "transcription": .object(["model": .string(Self.model)]),
                        "turn_detection": .object(["type": .string("server_vad")]),
                    ]),
                ]),
            ]),
        ])]
    }

    public func encodeChunk(_ pcm: Data) -> WebSocketMessage {
        AdapterJSON.text([
            "type": .string("input_audio_buffer.append"),
            "audio": .string(pcm.base64EncodedString()),
        ])
    }

    public func endMessages() -> [WebSocketMessage] {
        [AdapterJSON.text(["type": .string("input_audio_buffer.commit")])]
    }

    public mutating func handle(_ message: WebSocketMessage, emit: inout AdapterEmitter) throws -> Bool {
        guard let event = AdapterJSON.fields(message) else { return false }
        switch event["type"]?.stringValue {
        case "conversation.item.input_audio_transcription.delta":
            deltas += event["delta"]?.stringValue ?? ""
            emit.partial(deltas)
        case "conversation.item.input_audio_transcription.completed":
            deltas = ""
            emit.final(event["transcript"]?.stringValue ?? "")
            let usage = event["usage"]?.objectValue ?? [:]
            emit.addTokens(input: usage["input_tokens"]?.intValue, output: usage["output_tokens"]?.intValue)
            return true
        case "error":
            throw CloudAdapterError.provider(engine: name, detail: AdapterJSON.compact(event["error"]))
        default:
            break
        }
        return false
    }
}
