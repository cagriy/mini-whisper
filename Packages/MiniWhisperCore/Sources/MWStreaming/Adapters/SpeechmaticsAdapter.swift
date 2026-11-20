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
    /// R10, diarized sessions only: who to enrol. Nil leaves `StartRecognition` as it was (R2).
    private let voices: VoiceSessionConfig?

    public init(
        apiKey: String,
        hints: RecognitionHints = .none,
        diarization: Bool = false,
        model: String = "standard",
        voices: VoiceSessionConfig? = nil
    ) {
        headers = ["Authorization": "Bearer \(apiKey)"]
        vocabulary = HintSerializer.speechmaticsVocab(hints).sent
        self.diarization = diarization
        self.model = model
        self.voices = voices
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
            transcriptionConfig["speaker_diarization_config"] = .object(diarizationConfig())
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

    /// R12: a mid-session `GetSpeakers`, answered at once with a `SpeakersResult`.
    public func encode(_ command: EngineCommand) -> WebSocketMessage? {
        switch command {
        case .requestSpeakers:
            AdapterJSON.text(["message": .string("GetSpeakers"), "final": .bool(false)])
        }
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
        case "SpeakersResult":
            emit.speakers(Self.speakers(event["speakers"]))
        case "Warning":
            // R27: a warning's text is never logged or passed on.
            switch event["type"]?.stringValue {
            case "session_timeout":
                // Sent ahead of the 48 h session cap.
                emit.sessionLimit(.warning)
            case "speaker_id":
                let enrolled = ignoredSpeaker(event["reason"]?.stringValue)
                emit.identifierIgnored(label: enrolled?.label, identifier: enrolled?.identifier)
            default:
                break
            }
        case "Error":
            let type = event["type"]?.stringValue ?? "unknown"
            let reason = event["reason"]?.stringValue ?? ""
            throw CloudAdapterError.provider(engine: name, detail: "\(type): \(reason)")
        default:
            break
        }
        return false
    }

    private func diarizationConfig() -> [String: JSONValue] {
        var config: [String: JSONValue] = ["max_speakers": .number(10)]
        guard let voices else { return config }
        config["get_speakers"] = .bool(true)
        config["speaker_sensitivity"] = .number(voices.sensitivity)
        if !voices.speakers.isEmpty {
            config["speakers"] = .array(voices.speakers.map { speaker in
                .object([
                    "label": .string(speaker.label),
                    "speaker_identifiers": .array([.string(speaker.identifier)]),
                ])
            })
        }
        return config
    }

    /// The enrolled speaker a `speaker_id` warning names; nil unless its reason starts with
    /// 1-based indices of an identifier this session sent (one per speaker). Nothing else of the
    /// text is read.
    private func ignoredSpeaker(_ reason: String?) -> VoiceSessionConfig.Speaker? {
        let indices = /identifier '(\d+)', speaker '(\d+)'/.asciiOnlyDigits()
        guard let reason, let speakers = voices?.speakers,
              let match = reason.prefixMatch(of: indices),
              Int(match.output.1) == 1,
              let index = Int(match.output.2), speakers.indices.contains(index - 1)
        else { return nil }
        return speakers[index - 1]
    }

    /// Labels and identifiers are opaque provider strings; anything else is skipped.
    private static func speakers(_ value: JSONValue?) -> [ProviderSpeaker] {
        guard case .array(let entries)? = value else { return [] }
        return entries.compactMap { entry in
            guard let fields = entry.objectValue,
                  let label = fields["label"]?.stringValue,
                  case .array(let values)? = fields["speaker_identifiers"]
            else { return nil }
            let identifiers = values.compactMap(\.stringValue)
            return identifiers.isEmpty ? nil : ProviderSpeaker(label: label, identifiers: identifiers)
        }
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
