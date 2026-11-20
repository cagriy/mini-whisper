import Foundation
import MWConfig
import MWSupport
import MWTestSupport
import Testing

import MWStreaming

/// R2, R10, R12, R13, R27: the Speechmatics identification wire. The fixtures are written from
/// the shapes recorded in design §4, with placeholder identifiers.
@Suite struct SpeechmaticsVoiceTests {
    private static let key = "placeholder-not-a-real-key"
    private static let alice = "mw:00000000-0000-4000-8000-000000000001"
    private static let bob = "mw:00000000-0000-4000-8000-000000000002"
    private static let voices = VoiceSessionConfig(
        speakers: [
            VoiceSessionConfig.Speaker(label: alice, identifier: "placeholder-identifier-alice"),
            VoiceSessionConfig.Speaker(label: bob, identifier: "placeholder-identifier-bob"),
        ],
        sensitivity: 0.8
    )
    private static let unnamed = AdapterEmitter.Emission.identifierIgnored(label: nil, identifier: nil)

    private func adapter(model: String = "standard", voices: VoiceSessionConfig? = Self.voices) -> SpeechmaticsAdapter {
        SpeechmaticsAdapter(apiKey: Self.key, diarization: true, model: model, voices: voices)
    }

    // MARK: - StartRecognition and GetSpeakers

    /// R2. JSONEncoder orders a dictionary's keys per instance, so two builds of today's message
    /// differ in bytes; the guard is the exact JSON value.
    @Test func startRecognitionIsUnchangedWithoutVoices() throws {
        for model in ["standard", "enhanced"] {
            let today = SpeechmaticsAdapter(apiKey: Self.key, hints: .none, diarization: true, model: model)
            let withoutVoices = adapter(model: model, voices: nil)

            #expect(withoutVoices.openMessages().count == 1)
            #expect(try json(withoutVoices.openMessages().first) == json(today.openMessages().first))
            #expect(try json(withoutVoices.openMessages().first) == parse("""
            {"message": "StartRecognition",
             "audio_format": {"type": "raw", "encoding": "pcm_s16le", "sample_rate": 16000},
             "transcription_config": {"language": "en", "enable_partials": true,
                                      "diarization": "speaker",
                                      "speaker_diarization_config": {"max_speakers": 10},
                                      "model": "\(model)"}}
            """))
        }
    }

    @Test func voicesAddGetSpeakersSensitivityAndSpeakers() throws {
        let config = try #require(try transcriptionConfig(adapter(model: "enhanced")))

        #expect(config.keys.sorted() == [
            "diarization", "enable_partials", "language", "model", "speaker_diarization_config",
        ])
        #expect(config["model"] == .string("enhanced"))
        #expect(try config["speaker_diarization_config"] == parse("""
        {"max_speakers": 10, "get_speakers": true, "speaker_sensitivity": 0.8,
         "speakers": [
           {"label": "\(Self.alice)", "speaker_identifiers": ["placeholder-identifier-alice"]},
           {"label": "\(Self.bob)", "speaker_identifiers": ["placeholder-identifier-bob"]}]}
        """))
    }

    @Test func anEmptyEnrolmentOmitsSpeakers() throws {
        let config = try transcriptionConfig(adapter(voices: VoiceSessionConfig(speakers: [], sensitivity: 0.5)))

        #expect(try config?["speaker_diarization_config"] == parse("""
        {"max_speakers": 10, "get_speakers": true, "speaker_sensitivity": 0.5}
        """))
    }

    @Test func requestSpeakersEncodesGetSpeakersNotFinal() throws {
        for voices in [Self.voices, nil] {
            #expect(try json(adapter(voices: voices).encode(.requestSpeakers)) == parse("""
            {"final": false, "message": "GetSpeakers"}
            """))
        }
    }

    @Test func otherAdaptersEncodeNoCommand() {
        #expect(AssemblyAIAdapter(apiKey: Self.key).encode(.requestSpeakers) == nil)
        #expect(OpenAIRealtimeAdapter(apiKey: Self.key).encode(.requestSpeakers) == nil)
        #expect(ElevenLabsAdapter(apiKey: Self.key).encode(.requestSpeakers) == nil)
    }

    // MARK: - SpeakersResult and the speaker_id warning

    @Test func speakersResultEmitsEachLabelsIdentifiers() throws {
        #expect(try emissions(adapter(), fixture("speechmatics_speakers_result")) == [
            .speakers([
                ProviderSpeaker(label: "S1", identifiers: ["placeholder-identifier-s1"]),
                ProviderSpeaker(label: Self.bob, identifiers: ["placeholder-identifier-mw"]),
            ]),
        ])
    }

    /// The trust boundary: only a string label with at least one string identifier is kept.
    @Test func aMalformedSpeakersResultKeepsOnlyWellFormedEntries() throws {
        #expect(try emissions(adapter(), """
        {"message": "SpeakersResult",
         "speakers": [{"speaker_identifiers": ["placeholder-a"]},
                      {"label": 7, "speaker_identifiers": ["placeholder-b"]},
                      "S3",
                      {"label": "S4"},
                      {"label": "S5", "speaker_identifiers": [9, null]},
                      {"label": "S6", "speaker_identifiers": ["placeholder-c", 9, null]}]}
        """) == [.speakers([ProviderSpeaker(label: "S6", identifiers: ["placeholder-c"])])])
        #expect(try emissions(adapter(), #"{"message": "SpeakersResult"}"#) == [.speakers([])])
    }

    @Test func aSpeakerIdWarningNamesTheEnrolledLabelAndIdentifier() throws {
        #expect(try emissions(adapter(), fixture("speechmatics_speaker_id_warning")) == [
            .identifierIgnored(label: Self.bob, identifier: "placeholder-identifier-bob"),
        ])
        #expect(try emissions(adapter(), warning("identifier '1', speaker '1' - reason: x")) == [
            .identifierIgnored(label: Self.alice, identifier: "placeholder-identifier-alice"),
        ])
    }

    @Test func anUnparsedOrOutOfRangeWarningEmitsNils() throws {
        #expect(try emissions(adapter(), fixture("speechmatics_speaker_id_warning_unparsed")) == [Self.unnamed])
        #expect(try emissions(adapter(voices: nil), fixture("speechmatics_speaker_id_warning")) == [Self.unnamed])
        #expect(try emissions(adapter(), #"{"message": "Warning", "type": "speaker_id"}"#) == [Self.unnamed])
        for reason in [
            "identifier '1', speaker '3' - reason: past the enrolment",
            "identifier '1', speaker '0' - reason: indices are 1-based",
            "identifier '2', speaker '1' - reason: one identifier per speaker",
            "identifier '1', speaker '99999999999999999999' - reason: overflow",
            "note: identifier '1', speaker '1' - reason: the pattern is anchored",
        ] {
            #expect(try emissions(adapter(), warning(reason)) == [Self.unnamed], "\(reason)")
        }
    }

    @Test func theSessionTimeoutWarningStillRollsOver() throws {
        #expect(try emissions(adapter(), """
        {"message": "Warning", "type": "session_timeout", "reason": "Session will timeout in 15 minutes"}
        """) == [.sessionLimit(.warning)])
    }

    /// R27: the warning's text reaches neither the log nor the sink; only the enrolment's own
    /// label and identifier travel on.
    @Test func warningTextIsNeverLogged() async throws {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(
            script: FixtureScript(steps: [
                .awaitClient(.type("StartRecognition")),
                .server(try fixture("speechmatics_speaker_id_warning")),
                .server(try fixture("speechmatics_speaker_id_warning_unparsed")),
                .server(try fixture("speechmatics_speakers_result")),
                .awaitClient(.type("EndOfStream")),
                .server(#"{"message": "EndOfTranscript"}"#),
            ]),
            clock: clock
        )
        let logs = CapturingLogSink()
        let transcript = RecordingSink()
        let engine = WebSocketEngine(adapter: adapter(), clock: clock) { connection }

        let result = await Log.withSinks(debug: true, sinks: [logs]) {
            engine.start(sink: transcript)
            return await engine.finish(timeout: .seconds(5))
        }

        #expect(result.ok)
        #expect(transcript.ignored == [
            RecordingSink.Ignored(label: Self.bob, identifier: "placeholder-identifier-bob"),
            RecordingSink.Ignored(label: nil, identifier: nil),
        ])
        #expect(!logs.lines.isEmpty)
        for line in logs.lines {
            for text in ["incompatible", "identifier '", "reason", "placeholder-identifier", "mw:"] {
                #expect(!line.contains(text), "\(line)")
            }
        }
    }

    // MARK: - Harness

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/streaming")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func warning(_ reason: String) -> String {
        #"{"message": "Warning", "type": "speaker_id", "reason": "\#(reason)"}"#
    }

    /// What one server message makes the adapter emit, outside any engine.
    private func emissions(_ adapter: SpeechmaticsAdapter, _ message: String) throws -> [AdapterEmitter.Emission] {
        var adapter = adapter
        var emitter = AdapterEmitter()
        _ = try adapter.handle(.text(message), emit: &emitter)
        return emitter.emissions
    }

    private func json(_ message: WebSocketMessage?) throws -> JSONValue? {
        guard case .text(let text)? = message else { return nil }
        return try parse(text)
    }

    private func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func transcriptionConfig(_ adapter: SpeechmaticsAdapter) throws -> [String: JSONValue]? {
        guard case .object(let start)? = try json(adapter.openMessages().first),
              case .object(let config)? = start["transcription_config"]
        else { return nil }
        return config
    }
}
