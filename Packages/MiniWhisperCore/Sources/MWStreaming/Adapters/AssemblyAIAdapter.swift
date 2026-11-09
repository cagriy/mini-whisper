import Foundation
import MWConfig
import MWCorrections

/// AssemblyAI Universal-Streaming v3 websocket (design §5.3). Session configuration
/// travels in the URL query, which the provider does not validate: a misspelt
/// parameter is silently ignored.
public struct AssemblyAIAdapter: EngineAdapter {
    private static let endpoint = "wss://streaming.assemblyai.com/v3/ws"
    /// The provider rejects a chunk under 20 ms (close 3007).
    private static let shortestChunkBytes = 320 * MemoryLayout<Int16>.size
    /// Only unreserved characters pass: `&` would split a parameter and `+` reads as a space.
    private static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public let name = EngineName.assemblyai
    public let url: URL
    public let headers: [String: String]
    public let targetRate: Double = 16000
    /// A guard only: `Termination` is documented as the last message.
    public let drainAfterComplete = Duration.milliseconds(200)
    /// The provider recommends 50–100 ms; the capture tap delivers about 21 ms.
    public let minimumChunkSeconds: Double? = 0.1

    /// With formatting on, the unformatted end-of-turn precedes the formatted one and
    /// is only a partial.
    private let formatTurns: Bool

    public init(
        apiKey: String,
        hints: RecognitionHints = .none,
        model: String = "universal-streaming-english",
        speakerLabels: Bool = false,
        formatTurns: Bool = true
    ) {
        var query: [(String, String)] = [
            ("speech_model", model),
            ("encoding", "pcm_s16le"),
            ("sample_rate", "16000"),
        ]
        if speakerLabels {
            query += [
                ("speaker_labels", "true"),
                ("max_speakers", "10"),
                ("speaker_labels_revision_interval_ms", "300000"),
            ]
        }
        if formatTurns { query.append(("format_turns", "true")) }
        let keyterms = HintSerializer.assemblyAIKeyterms(hints).sent
        if !keyterms.isEmpty {
            query.append(("keyterms_prompt", AdapterJSON.compact(.array(keyterms.map(JSONValue.string)))))
        }
        let encoded = query.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) ?? "")"
        }
        url = URL(string: Self.endpoint + "?" + encoded.joined(separator: "&"))!
        headers = ["Authorization": apiKey]
        self.formatTurns = formatTurns
    }

    public func openMessages() -> [WebSocketMessage] { [] }

    /// Audio goes as raw binary frames; a short one is padded with silence.
    public func encodeChunk(_ pcm: Data) -> WebSocketMessage {
        guard pcm.count < Self.shortestChunkBytes else { return .binary(pcm) }
        return .binary(pcm + Data(count: Self.shortestChunkBytes - pcm.count))
    }

    public func endMessages() -> [WebSocketMessage] {
        [AdapterJSON.text(["type": .string("Terminate")])]
    }

    public func handle(_ message: WebSocketMessage, emit: inout AdapterEmitter) throws -> Bool {
        guard let event = AdapterJSON.fields(message) else { return false }
        if event["type"]?.stringValue == "Error" || event["error"] != nil {
            throw CloudAdapterError.provider(engine: name, detail: AdapterJSON.compact(.object(event)))
        }
        switch event["type"]?.stringValue {
        case "Begin":
            if case .number(let seconds)? = event["expires_at"] {
                emit.sessionLimit(.expiresAt(Date(timeIntervalSince1970: seconds)))
            }
        case "Turn":
            turn(event, emit: &emit)
        case "SpeakerRevision":
            guard case .array(let revisions)? = event["revisions"] else { break }
            emit.speakerRevision(revisions.compactMap { revision in
                guard let fields = revision.objectValue,
                      let turnOrder = fields["turn_order"]?.intValue,
                      let speaker = fields["speaker_label"]?.stringValue
                else { return nil }
                return SpeakerRevision(turnOrder: turnOrder, speaker: speaker, words: Self.words(fields["words"]))
            })
        case "Termination":
            return true
        default:
            break
        }
        return false
    }

    private func turn(_ event: [String: JSONValue], emit: inout AdapterEmitter) {
        let transcript = event["transcript"]?.stringValue ?? ""
        let endOfTurn = event["end_of_turn"] == .bool(true)
        let formatted = event["turn_is_formatted"] == .bool(true)
        guard endOfTurn, formatted || !formatTurns else {
            emit.partial(transcript)
            return
        }
        emit.final(transcript)
        let words = Self.words(event["words"])
        emit.segment(TranscriptSegment(
            text: transcript,
            words: words,
            speaker: Self.speaker(event["speaker_label"]),
            turnOrder: event["turn_order"]?.intValue,
            start: words.first?.start ?? 0,
            end: words.last?.end ?? 0
        ))
    }

    /// `PENDING` marks a turn too short to attribute; `UNKNOWN` likewise names no one.
    private static func speaker(_ label: JSONValue?) -> String? {
        guard let label = label?.stringValue, !["", "PENDING", "UNKNOWN"].contains(label) else { return nil }
        return label
    }

    /// Word times arrive in milliseconds.
    private static func words(_ value: JSONValue?) -> [TranscriptWord] {
        guard case .array(let words)? = value else { return [] }
        return words.compactMap { word in
            guard let fields = word.objectValue,
                  let text = fields["text"]?.stringValue,
                  case .number(let start)? = fields["start"],
                  case .number(let end)? = fields["end"]
            else { return nil }
            return TranscriptWord(text: text, start: start / 1000, end: end / 1000)
        }
    }
}
