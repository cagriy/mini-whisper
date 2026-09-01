import Foundation
import MWConfig

/// ElevenLabs Scribe v2 Realtime websocket, pinned to design §5.4.
public struct ElevenLabsAdapter: EngineAdapter {
    public let name = EngineName.elevenlabs
    public let url = URL(
        string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
            + "?model_id=scribe_v2_realtime&audio_format=pcm_16000"
    )!
    public let headers: [String: String]
    public let targetRate: Double = 16000
    /// A VAD-committed segment can race our committing chunk, as with OpenAI.
    public let drainAfterComplete = Duration.milliseconds(200)

    public init(apiKey: String) {
        headers = ["xi-api-key": apiKey]
    }

    /// Session configuration travels in the URL query parameters.
    public func openMessages() -> [WebSocketMessage] { [] }

    public func encodeChunk(_ pcm: Data) -> WebSocketMessage {
        chunk(base64: pcm.base64EncodedString(), commit: false)
    }

    public func endMessages() -> [WebSocketMessage] {
        [chunk(base64: "", commit: true)]
    }

    public func handle(_ message: WebSocketMessage, emit: inout AdapterEmitter) throws -> Bool {
        guard let event = AdapterJSON.fields(message) else { return false }
        switch event["message_type"]?.stringValue {
        case "partial_transcript", "final_transcript":
            // `final_transcript` is settled but not yet committed: still a partial.
            emit.partial(event["text"]?.stringValue ?? "")
        case "committed_transcript":
            emit.final(event["text"]?.stringValue ?? "")
            return true
        case "input_error":
            throw CloudAdapterError.provider(engine: name, detail: AdapterJSON.compact(.object(event)))
        default:
            break
        }
        return false
    }

    private func chunk(base64: String, commit: Bool) -> WebSocketMessage {
        AdapterJSON.text([
            "message_type": .string("input_audio_chunk"),
            "audio_base_64": .string(base64),
            "commit": .bool(commit),
            "sample_rate": .number(targetRate),
        ])
    }
}
