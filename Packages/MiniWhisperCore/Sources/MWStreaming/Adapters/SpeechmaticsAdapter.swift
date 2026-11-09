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
    /// Meetings only: speaker labels and a chosen `model`, both off the dictation wire.
    private let diarization: Bool
    /// `standard` or `enhanced`; `operating_point` is its deprecated alias.
    private let model: String

    public init(
        apiKey: String,
        hints: RecognitionHints = .none,
        diarization: Bool = false,
        model: String = "standard"
    ) {
        headers = ["Authorization": "Bearer \(apiKey)"]
        vocabulary = HintSerializer.speechmaticsVocab(hints).sent
        self.diarization = diarization
        self.model = model
    }

    public func openMessages() -> [WebSocketMessage] {
        var transcriptionConfig: [String: JSONValue] = [
            "language": .string("en"),
            "enable_partials": .bool(true),
        ]
        if !vocabulary.isEmpty {
            transcriptionConfig["additional_vocab"] = .array(vocabulary.map(Self.entry))
        }
        if diarization {
            transcriptionConfig["diarization"] = .string("speaker")
            transcriptionConfig["speaker_diarization_config"] = .object(["max_speakers": .number(10)])
            transcriptionConfig["model"] = .string(model)
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
            if diarization {
                for segment in Self.segments(event["results"]) { emit.segment(segment) }
            }
        case "EndOfTranscript":
            return true
        case "Warning":
            // Sent ahead of the 48 h session cap; other warnings need no action.
            if event["type"]?.stringValue == "session_timeout" { emit.sessionLimit(.warning) }
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

    /// One segment per run of consecutive results sharing a speaker (`UU` → nil).
    /// Punctuation joins the word before it, whatever its own label.
    private static func segments(_ results: JSONValue?) -> [TranscriptSegment] {
        guard case .array(let results)? = results else { return [] }
        var runs: [(speaker: String?, words: [TranscriptWord])] = []
        for case .object(let result) in results {
            guard case .array(let alternatives)? = result["alternatives"],
                  let best = alternatives.first?.objectValue,
                  let content = best["content"]?.stringValue
            else { continue }
            if result["type"]?.stringValue == "punctuation", let run = runs.indices.last {
                runs[run].words[runs[run].words.count - 1].text += content
                continue
            }
            guard case .number(let start)? = result["start_time"],
                  case .number(let end)? = result["end_time"]
            else { continue }
            let word = TranscriptWord(text: content, start: start, end: end)
            let speaker = best["speaker"]?.stringValue.flatMap { $0 == "UU" ? nil : $0 }
            if let run = runs.indices.last, runs[run].speaker == speaker {
                runs[run].words.append(word)
            } else {
                runs.append((speaker, [word]))
            }
        }
        return runs.map { run in
            TranscriptSegment(
                text: run.words.map(\.text).joined(separator: " "),
                words: run.words,
                speaker: run.speaker,
                start: run.words[0].start,
                end: run.words[run.words.count - 1].end
            )
        }
    }
}
