import Foundation
import MWConfig
import MWCorrections

/// Speechmatics Real-Time v2 websocket, pinned to design §5.4.
public struct SpeechmaticsAdapter: EngineAdapter {
    public let name = EngineName.speechmatics
    public let url = URL(string: "wss://eu.rt.speechmatics.com/v2")!
    public let headers: [String: String]
    public let targetRate: Double = 16000
    /// `EndOfTranscript` is a hard terminal: nothing follows it, so no drain.
    public let drainAfterComplete = Duration.zero

    /// Binary AddAudio frames sent so far, declared back in `EndOfStream`.
    private var sequenceNumber = 0
    /// R21, already capped and filtered to what the provider accepts.
    private let vocabulary: [HintSerializer.VocabEntry]

    public init(apiKey: String, hints: RecognitionHints = .none) {
        headers = ["Authorization": "Bearer \(apiKey)"]
        vocabulary = HintSerializer.speechmaticsVocab(hints).sent
    }

    public func openMessages() -> [WebSocketMessage] {
        var transcriptionConfig: [String: JSONValue] = [
            "language": .string("en"),
            "enable_partials": .bool(true),
        ]
        if !vocabulary.isEmpty {
            transcriptionConfig["additional_vocab"] = .array(vocabulary.map(Self.entry))
        }
        return [AdapterJSON.text([
            "message": .string("StartRecognition"),
            "audio_format": .object([
                "type": .string("raw"),
                "encoding": .string("pcm_s16le"),
                "sample_rate": .number(targetRate),
            ]),
            "transcription_config": .object(transcriptionConfig),
        ])]
    }

    /// Audio goes as raw binary AddAudio frames.
    public mutating func encodeChunk(_ pcm: Data) -> WebSocketMessage {
        sequenceNumber += 1
        return .binary(pcm)
    }

    public func endMessages() -> [WebSocketMessage] {
        [AdapterJSON.text([
            "message": .string("EndOfStream"),
            "last_seq_no": .number(Double(sequenceNumber)),
        ])]
    }

    public func handle(_ message: WebSocketMessage, emit: inout AdapterEmitter) throws -> Bool {
        // Binary server frames carry no transcript and are ignored.
        guard let event = AdapterJSON.fields(message) else { return false }
        switch event["message"]?.stringValue {
        case "AddPartialTranscript":
            emit.partial(transcript(event))
        case "AddTranscript":
            emit.final(transcript(event))
        case "EndOfTranscript":
            return true
        case "Error":
            let type = event["type"]?.stringValue ?? "unknown"
            let reason = event["reason"]?.stringValue ?? ""
            throw CloudAdapterError.provider(engine: name, detail: "\(type): \(reason)")
        default:
            break
        }
        return false
    }

    private static func entry(_ entry: HintSerializer.VocabEntry) -> JSONValue {
        var fields: [String: JSONValue] = ["content": .string(entry.content)]
        if !entry.soundsLike.isEmpty {
            fields["sounds_like"] = .array(entry.soundsLike.map(JSONValue.string))
        }
        return .object(fields)
    }

    private func transcript(_ event: [String: JSONValue]) -> String {
        event["metadata"]?.objectValue?["transcript"]?.stringValue ?? ""
    }
}
