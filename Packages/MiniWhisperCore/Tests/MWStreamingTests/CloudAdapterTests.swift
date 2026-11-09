import Foundation
import MWAudio
import MWConfig
import MWCorrections
import MWSupport
import MWTestSupport
import Testing

import MWStreaming

/// The cloud adapters against the wire protocols pinned in design §5.4,
/// replayed through the fixture transcripts ported from
/// `../mini-whisper-py/tests/fixtures/streaming/` (Python `test_websocket_engines.py`
/// cases 260–380).
@Suite struct CloudAdapterTests {
    private static let key = "placeholder-not-a-real-key"
    private static let slack = "com.tinyspeck.slackmacgap"

    /// Design §5.3's worked example: one app rule, one global rule, one vocabulary term.
    private static let hints = HintResolver.resolve(
        CorrectionSnapshot(
            rules: [
                CorrectionRule(
                    heard: "eefa", write: "Aoife", soundsLike: ["eva"], bundleID: slack
                ),
                CorrectionRule(heard: "get hub", write: "GitHub"),
            ],
            vocabulary: ["xcodegen"]
        ),
        bundleID: slack
    )

    // MARK: - OpenAI Realtime

    @Test func openAIHappyPathFixture() async throws {
        let replay = try await replay(
            adapter: OpenAIRealtimeAdapter(apiKey: Self.key),
            fixture: "openai_realtime",
            chunks: [[Float](repeating: 0, count: 4800)]
        )

        #expect(replay.result.ok)
        #expect(replay.result.text == "hello world again")
        #expect(replay.sink.partials == ["hello", "hello world", "again"])
        #expect(replay.sink.finals == ["hello world", "again"])
        #expect(replay.result.usage.inputTokens == 12)
        #expect(replay.result.usage.outputTokens == 4)
        #expect(abs(replay.result.usage.seconds - 0.1) < 1e-9)
        // The first `completed` arrives before the commit and must not end the
        // session — otherwise "again" would never be transcribed.
        #expect(replay.connection.sentTypes == [
            "session.update", "input_audio_buffer.append", "input_audio_buffer.commit",
        ])
    }

    @Test func openAISessionUpdateShape() async throws {
        let adapter = OpenAIRealtimeAdapter(apiKey: Self.key)
        #expect(adapter.name == .openai)
        #expect(adapter.url.absoluteString == "wss://api.openai.com/v1/realtime")
        #expect(adapter.headers == ["Authorization": "Bearer \(Self.key)"])

        let replay = try await replay(adapter: adapter, fixture: "openai_realtime", chunks: [chunk()])

        #expect(try json(replay.connection.sentMessages.first) == parse("""
        {"type": "session.update",
         "session": {"type": "transcription",
                     "audio": {"input": {"format": {"type": "audio/pcm", "rate": 24000},
                                         "transcription": {"model": "gpt-live-transcribe"},
                                         "turn_detection": {"type": "server_vad"}}}}}
        """))
    }

    @Test func openAISessionUpdateCarriesKeywords() async throws {
        let replay = try await replay(
            adapter: OpenAIRealtimeAdapter(apiKey: Self.key, hints: Self.hints),
            fixture: "openai_realtime",
            chunks: [chunk()]
        )

        #expect(try json(replay.connection.sentMessages.first) == parse("""
        {"type": "session.update",
         "session": {"type": "transcription",
                     "audio": {"input": {"format": {"type": "audio/pcm", "rate": 24000},
                                         "transcription": {"model": "gpt-live-transcribe",
                                                           "keywords": ["Aoife", "eefa", "eva",
                                                                        "GitHub", "get hub",
                                                                        "xcodegen"]},
                                         "turn_detection": {"type": "server_vad"}}}}}
        """))
    }

    @Test func openAIChunkAndCommitShapes() async throws {
        let samples = chunk()
        let replay = try await replay(
            adapter: OpenAIRealtimeAdapter(apiKey: Self.key),
            fixture: "openai_realtime",
            chunks: [samples]
        )

        var converter = PCMConverter(from: 48000, to: 24000)
        #expect(try json(replay.connection.sentMessages[1]) == .object([
            "type": .string("input_audio_buffer.append"),
            "audio": .string(converter.convert(samples).base64EncodedString()),
        ]))
        #expect(try json(replay.connection.sentMessages.last) == .object([
            "type": .string("input_audio_buffer.commit"),
        ]))
    }

    @Test func openAIErrorEventFails() async {
        let replay = await replayFailure(
            adapter: OpenAIRealtimeAdapter(apiKey: Self.key),
            script: FixtureScript(steps: [
                .awaitClient(.type("session.update")),
                .server(#"{"type": "error", "error": {"message": "invalid_request"}}"#),
            ])
        )

        #expect(replay.result.ok == false)
        #expect(replay.sink.errors.count == 1)
    }

    // MARK: - ElevenLabs Scribe v2 Realtime

    @Test func elevenLabsHappyPathFixture() async throws {
        let replay = try await replay(
            adapter: ElevenLabsAdapter(apiKey: Self.key),
            fixture: "elevenlabs",
            chunks: [[Float](repeating: 0, count: 4800)]
        )

        #expect(replay.result.ok)
        #expect(replay.result.text == "hello world again")
        // `final_transcript` is settled but not committed, so it lands as a partial.
        #expect(replay.sink.partials == ["hello", "hello world", "hello world", "again"])
        #expect(replay.sink.finals == ["hello world", "again"])
        #expect(replay.result.usage.inputTokens == 0)
        #expect(replay.result.usage.outputTokens == 0)
        #expect(abs(replay.result.usage.seconds - 0.1) < 1e-9)
        // Session configuration travels in the URL query: no open message.
        #expect(replay.connection.sentTypes == ["input_audio_chunk", "input_audio_chunk"])
    }

    @Test func elevenLabsMessageShapes() async throws {
        let adapter = ElevenLabsAdapter(apiKey: Self.key)
        #expect(adapter.name == .elevenlabs)
        #expect(adapter.url.absoluteString == "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
            + "?model_id=scribe_v2_realtime&audio_format=pcm_16000")
        #expect(adapter.headers == ["xi-api-key": Self.key])

        let samples = chunk()
        let replay = try await replay(adapter: adapter, fixture: "elevenlabs", chunks: [samples])

        var converter = PCMConverter(from: 48000, to: 16000)
        #expect(try json(replay.connection.sentMessages.first) == .object([
            "message_type": .string("input_audio_chunk"),
            "audio_base_64": .string(converter.convert(samples).base64EncodedString()),
            "commit": .bool(false),
            "sample_rate": .number(16000),
        ]))
        #expect(try json(replay.connection.sentMessages.last) == .object([
            "message_type": .string("input_audio_chunk"),
            "audio_base_64": .string(""),
            "commit": .bool(true),
            "sample_rate": .number(16000),
        ]))
    }

    @Test func elevenLabsInputErrorFails() async {
        let replay = await replayFailure(
            adapter: ElevenLabsAdapter(apiKey: Self.key),
            script: FixtureScript(steps: [
                .server(#"{"message_type": "input_error", "error": "unsupported audio format"}"#),
            ])
        )

        #expect(replay.result.ok == false)
        #expect(replay.sink.errors.count == 1)
    }

    // MARK: - Speechmatics Real-Time v2

    @Test func speechmaticsHappyPathFixture() async throws {
        let replay = try await replay(
            adapter: SpeechmaticsAdapter(apiKey: Self.key),
            fixture: "speechmatics",
            chunks: [[Float](repeating: 0, count: 4800)]
        )

        #expect(replay.result.ok)
        #expect(replay.result.text == "hello world again")
        #expect(replay.sink.partials == ["hello", "hello world", "again"])
        #expect(replay.sink.finals == ["hello world ", "again"])
        #expect(replay.result.usage.inputTokens == 0)
        #expect(replay.result.usage.outputTokens == 0)
        #expect(abs(replay.result.usage.seconds - 0.1) < 1e-9)
        #expect(replay.connection.sentTypes == ["StartRecognition", "__binary__", "EndOfStream"])
    }

    @Test func speechmaticsMessageShapes() async throws {
        let adapter = SpeechmaticsAdapter(apiKey: Self.key)
        #expect(adapter.name == .speechmatics)
        #expect(adapter.url.absoluteString == "wss://eu.rt.speechmatics.com/v2")
        #expect(adapter.headers == ["Authorization": "Bearer \(Self.key)"])

        let first = chunk()
        let second = SignalFixtures.ramp(count: 4800, from: 0.5, to: -0.5)
        let replay = try await replay(adapter: adapter, fixture: "speechmatics", chunks: [first, second])

        #expect(try json(replay.connection.sentMessages.first) == parse("""
        {"message": "StartRecognition",
         "audio_format": {"type": "raw", "encoding": "pcm_s16le", "sample_rate": 16000},
         "transcription_config": {"language": "en", "enable_partials": true}}
        """))
        var converter = PCMConverter(from: 48000, to: 16000)
        #expect(replay.connection.binaryPayloads == [converter.convert(first), converter.convert(second)])
        #expect(try json(replay.connection.sentMessages.last) == .object([
            "message": .string("EndOfStream"),
            "last_seq_no": .number(2),
        ]))
    }

    @Test func speechmaticsStartRecognitionCarriesAdditionalVocab() async throws {
        let replay = try await replay(
            adapter: SpeechmaticsAdapter(apiKey: Self.key, hints: Self.hints),
            fixture: "speechmatics",
            chunks: [chunk()]
        )

        #expect(try json(replay.connection.sentMessages.first) == parse("""
        {"message": "StartRecognition",
         "audio_format": {"type": "raw", "encoding": "pcm_s16le", "sample_rate": 16000},
         "transcription_config": {"language": "en", "enable_partials": true,
                                  "additional_vocab": [
                                      {"content": "Aoife", "sounds_like": ["eefa", "eva"]},
                                      {"content": "GitHub", "sounds_like": ["get hub"]},
                                      {"content": "xcodegen"}]}}
        """))
    }

    /// Guards dictation's wire: diarization and the model ride on meetings only.
    @Test func speechmaticsWithoutDiarizationSendsNoDiarizationOrModel() throws {
        let plain = try transcriptionConfig(SpeechmaticsAdapter(apiKey: Self.key))
        let hinted = try transcriptionConfig(SpeechmaticsAdapter(apiKey: Self.key, hints: Self.hints))

        #expect(plain.keys.sorted() == ["enable_partials", "language"])
        #expect(hinted.keys.sorted() == ["additional_vocab", "enable_partials", "language"])
    }

    @Test func speechmaticsWithoutDiarizationEmitsNoSegments() throws {
        let emissions = try emissions(SpeechmaticsAdapter(apiKey: Self.key), Self.diarizedTranscript)

        #expect(emissions == [.final("Hello there. ")])
    }

    @Test func speechmaticsDiarizedStartRecognitionShape() throws {
        let enhanced = SpeechmaticsAdapter(apiKey: Self.key, hints: .none, diarization: true, model: "enhanced")
        let standard = SpeechmaticsAdapter(apiKey: Self.key, diarization: true)
        let undiarized = SpeechmaticsAdapter(apiKey: Self.key, diarization: false, model: "enhanced")

        #expect(try json(enhanced.openMessages().first) == parse("""
        {"message": "StartRecognition",
         "audio_format": {"type": "raw", "encoding": "pcm_s16le", "sample_rate": 16000},
         "transcription_config": {"language": "en", "enable_partials": true,
                                  "diarization": "speaker",
                                  "speaker_diarization_config": {"max_speakers": 10},
                                  "model": "enhanced"}}
        """))
        #expect(try transcriptionConfig(standard)["model"] == .string("standard"))
        #expect(try transcriptionConfig(undiarized).keys.sorted() == ["enable_partials", "language"])
    }

    @Test func speechmaticsDiarizedFixtureEmitsSegmentsSplitBySpeaker() async throws {
        let replay = try await replay(
            adapter: SpeechmaticsAdapter(apiKey: Self.key, diarization: true),
            fixture: "speechmatics_diarized",
            chunks: [chunk()]
        )

        #expect(replay.sink.segments == [
            TranscriptSegment(
                text: "Hello there.",
                words: [
                    TranscriptWord(text: "Hello", start: 0.5, end: 0.82),
                    TranscriptWord(text: "there.", start: 0.82, end: 1.1),
                ],
                speaker: "S1", start: 0.5, end: 1.1
            ),
            TranscriptSegment(
                text: "Hi Marta.",
                words: [
                    TranscriptWord(text: "Hi", start: 1.6, end: 1.84),
                    TranscriptWord(text: "Marta.", start: 1.84, end: 2.4),
                ],
                speaker: "S2", start: 1.6, end: 2.4
            ),
            // `UU`: the provider could not tell who spoke.
            TranscriptSegment(
                text: "Right.",
                words: [TranscriptWord(text: "Right.", start: 2.9, end: 3.2)],
                speaker: nil, start: 2.9, end: 3.2
            ),
        ])
    }

    @Test func speechmaticsDiarizedFixtureStillEmitsFinals() async throws {
        let replay = try await replay(
            adapter: SpeechmaticsAdapter(apiKey: Self.key, diarization: true),
            fixture: "speechmatics_diarized",
            chunks: [chunk()]
        )

        #expect(replay.result.ok)
        #expect(replay.result.text == "Hello there. Hi Marta. Right.")
        #expect(replay.sink.partials == ["Hello there"])
        #expect(replay.sink.finals == ["Hello there. Hi Marta. ", "Right."])
    }

    @Test func speechmaticsPunctuationJoinsThePrecedingWordsRun() throws {
        let emissions = try emissions(SpeechmaticsAdapter(apiKey: Self.key, diarization: true), """
        {"message": "AddTranscript", "metadata": {"transcript": "Yes. "},
         "results": [
           {"type": "word", "start_time": 4.0, "end_time": 4.3, "alternatives": [{"content": "Yes", "speaker": "S1"}]},
           {"type": "punctuation", "start_time": 4.3, "end_time": 4.3, "attaches_to": "previous",
            "alternatives": [{"content": "."}]}]}
        """)

        #expect(emissions == [
            .final("Yes. "),
            .segment(TranscriptSegment(
                text: "Yes.", words: [TranscriptWord(text: "Yes.", start: 4.0, end: 4.3)],
                speaker: "S1", start: 4.0, end: 4.3
            )),
        ])
    }

    @Test func speechmaticsSessionTimeoutWarningEmitsSessionLimit() throws {
        let emissions = try emissions(SpeechmaticsAdapter(apiKey: Self.key, diarization: true), """
        {"message": "Warning", "type": "session_timeout", "reason": "Session will timeout in 15 minutes"}
        """)

        #expect(emissions == [.sessionLimit(.warning)])
    }

    @Test func speechmaticsOtherWarningsAreIgnored() throws {
        for type in ["idle_timeout", "duration_limit_exceeded", "add_audio_after_eos"] {
            let emissions = try emissions(SpeechmaticsAdapter(apiKey: Self.key, diarization: true), """
            {"message": "Warning", "type": "\(type)", "reason": "test"}
            """)
            #expect(emissions == [], "\(type)")
        }
    }

    @Test func speechmaticsErrorFails() async {
        let replay = await replayFailure(
            adapter: SpeechmaticsAdapter(apiKey: Self.key),
            script: FixtureScript(steps: [
                .awaitClient(.type("StartRecognition")),
                .server(#"{"message": "Error", "type": "invalid_audio_type", "reason": "bad encoding"}"#),
            ])
        )

        #expect(replay.result.ok == false)
        #expect(replay.sink.errors.count == 1)
    }

    @Test func speechmaticsIgnoresBinaryServerFrames() throws {
        var adapter = SpeechmaticsAdapter(apiKey: Self.key)
        var emitter = AdapterEmitter()

        let complete = try adapter.handle(.binary(Data([0x01, 0x02])), emit: &emitter)

        #expect(complete == false)
        #expect(emitter == AdapterEmitter())
    }

    // MARK: - AssemblyAI Universal-Streaming v3

    @Test func assemblyAIDictationURLAndHeader() throws {
        let adapter = AssemblyAIAdapter(
            apiKey: Self.key, model: "universal-streaming-english", speakerLabels: false, formatTurns: true
        )

        #expect(adapter.name == .assemblyai)
        #expect(try endpoint(adapter.url) == "wss://streaming.assemblyai.com/v3/ws")
        // AssemblyAI ignores a misspelt parameter, so the whole set is pinned.
        #expect(try query(adapter.url) == [
            "speech_model": "universal-streaming-english",
            "encoding": "pcm_s16le",
            "sample_rate": "16000",
            "format_turns": "true",
        ])
        // The raw key, no `Bearer`, and nowhere else.
        #expect(adapter.headers == ["Authorization": Self.key])
        #expect(!adapter.url.absoluteString.contains(Self.key))
        #expect(adapter.openMessages().isEmpty)
    }

    @Test func assemblyAIDiarizedURLCarriesSpeakerParams() throws {
        let adapter = AssemblyAIAdapter(
            apiKey: Self.key, model: "universal-3-6-pro", speakerLabels: true, formatTurns: false
        )

        #expect(try query(adapter.url) == [
            "speech_model": "universal-3-6-pro",
            "encoding": "pcm_s16le",
            "sample_rate": "16000",
            "speaker_labels": "true",
            "max_speakers": "10",
            "speaker_labels_revision_interval_ms": "300000",
        ])
    }

    @Test func assemblyAIKeytermsPromptIsAJSONArray() throws {
        let adapter = AssemblyAIAdapter(apiKey: Self.key, hints: Self.hints)
        let keyterms = try #require(try query(adapter.url)["keyterms_prompt"])

        #expect(try parse(keyterms) == .array(
            ["Aoife", "eefa", "eva", "GitHub", "get hub", "xcodegen"].map(JSONValue.string)
        ))
        #expect(try query(AssemblyAIAdapter(apiKey: Self.key).url)["keyterms_prompt"] == nil)
    }

    /// `&` would split the parameter and a bare `+` reads as a space.
    @Test func assemblyAIKeytermsAreStrictlyPercentEncoded() throws {
        let adapter = AssemblyAIAdapter(
            apiKey: Self.key, hints: RecognitionHints(terms: ["R&D", "C++"], rules: [], vocabulary: [])
        )

        #expect(adapter.url.query?.hasSuffix("&keyterms_prompt=%5B%22R%26D%22%2C%22C%2B%2B%22%5D") == true)
        #expect(try parse(try #require(try query(adapter.url)["keyterms_prompt"]))
            == .array([.string("R&D"), .string("C++")]))
    }

    @Test func assemblyAIHappyPathFixture() async throws {
        let replay = try await replay(
            adapter: AssemblyAIAdapter(apiKey: Self.key),
            fixture: "assemblyai",
            chunks: [[Float](repeating: 0, count: 4800)]
        )

        #expect(replay.result.ok)
        #expect(replay.result.text == "Hello world. Again.")
        #expect(replay.sink.partials == ["hello", "hello world", "hello world", "again", "again"])
        #expect(replay.sink.finals == ["Hello world.", "Again."])
        #expect(abs(replay.result.usage.seconds - 0.1) < 1e-9)
        // 100 ms of audio is exactly one minimum chunk: 1600 int16 samples.
        #expect(replay.connection.binaryPayloads.map(\.count) == [3200])
        #expect(replay.connection.sentTypes == ["__binary__", "Terminate"])
    }

    @Test func assemblyAIUnformattedEndOfTurnIsPartialWhenFormatting() throws {
        let emissions = try emissions(AssemblyAIAdapter(apiKey: Self.key, formatTurns: true), """
        {"type": "Turn", "turn_order": 0, "turn_is_formatted": false, "end_of_turn": true,
         "transcript": "my name is sonny", "words": []}
        """)

        #expect(emissions == [.partial("my name is sonny")])
    }

    @Test func assemblyAIProFinalisesOnEndOfTurnWithoutFormatting() throws {
        let emissions = try emissions(
            AssemblyAIAdapter(apiKey: Self.key, model: "universal-3-6-pro", formatTurns: false),
            """
            {"type": "Turn", "turn_order": 4, "turn_is_formatted": false, "end_of_turn": true,
             "transcript": "My name is Sonny.",
             "words": [{"text": "My", "start": 0, "end": 100}, {"text": "Sonny.", "start": 600, "end": 900}]}
            """
        )

        #expect(emissions == [
            .final("My name is Sonny."),
            .segment(TranscriptSegment(
                text: "My name is Sonny.",
                words: [
                    TranscriptWord(text: "My", start: 0, end: 0.1),
                    TranscriptWord(text: "Sonny.", start: 0.6, end: 0.9),
                ],
                turnOrder: 4, start: 0, end: 0.9
            )),
        ])
    }

    @Test func assemblyAIBeginEmitsExpiresAt() throws {
        let emissions = try emissions(AssemblyAIAdapter(apiKey: Self.key), """
        {"type": "Begin", "id": "3207b601-2054-48df-ba77-8784dfcf9fb8", "expires_at": 1772570132}
        """)

        #expect(emissions == [.sessionLimit(.expiresAt(Date(timeIntervalSince1970: 1_772_570_132)))])
    }

    @Test func assemblyAIWordTimesAreConvertedFromMilliseconds() throws {
        let emissions = try emissions(AssemblyAIAdapter(apiKey: Self.key, speakerLabels: true), """
        {"type": "Turn", "turn_order": 0, "turn_is_formatted": true, "end_of_turn": true,
         "transcript": "Good morning.", "speaker_label": "A",
         "words": [{"text": "Good", "start": 120, "end": 280, "speaker": "A"},
                   {"text": "morning.", "start": 280, "end": 3530, "speaker": "A"}]}
        """)
        guard case .segment(let segment)? = emissions.last else {
            Issue.record("no segment in \(emissions)")
            return
        }

        #expect(segment.words == [
            TranscriptWord(text: "Good", start: 0.12, end: 0.28),
            TranscriptWord(text: "morning.", start: 0.28, end: 3.53),
        ])
        #expect(segment.start == 0.12)
        #expect(segment.end == 3.53)
    }

    @Test func assemblyAITurnEmitsASegmentWithTurnOrderAndSpeaker() async throws {
        let replay = try await replay(
            adapter: AssemblyAIAdapter(
                apiKey: Self.key, model: "universal-3-6-pro", speakerLabels: true, formatTurns: false
            ),
            fixture: "assemblyai_diarized",
            chunks: [chunk()]
        )

        #expect(replay.result.ok)
        #expect(replay.result.text == "Hello there. Hi Marta. Right.")
        #expect(replay.sink.partials == ["Hello there"])
        #expect(replay.sink.limits == [.expiresAt(Date(timeIntervalSince1970: 1_772_580_000))])
        #expect(replay.sink.segments == [
            TranscriptSegment(
                text: "Hello there.",
                words: [
                    TranscriptWord(text: "Hello", start: 0.5, end: 0.82),
                    TranscriptWord(text: "there.", start: 0.82, end: 1.1),
                ],
                speaker: "A", turnOrder: 0, start: 0.5, end: 1.1
            ),
            TranscriptSegment(
                text: "Hi Marta.",
                words: [
                    TranscriptWord(text: "Hi", start: 1.6, end: 1.84),
                    TranscriptWord(text: "Marta.", start: 1.84, end: 2.4),
                ],
                speaker: "B", turnOrder: 1, start: 1.6, end: 2.4
            ),
            // Under about a second of audio the turn's label is `PENDING`: no speaker yet.
            TranscriptSegment(
                text: "Right.",
                words: [TranscriptWord(text: "Right.", start: 2.9, end: 3.2)],
                speaker: nil, turnOrder: 2, start: 2.9, end: 3.2
            ),
        ])
    }

    @Test func assemblyAIUnknownOrMissingSpeakerIsNil() throws {
        for label in [#""speaker_label": "UNKNOWN","#, #""speaker_label": "PENDING","#, ""] {
            let emissions = try emissions(AssemblyAIAdapter(apiKey: Self.key, speakerLabels: true), """
            {"type": "Turn", "turn_order": 0, "turn_is_formatted": true, "end_of_turn": true, \(label)
             "transcript": "Right.", "words": [{"text": "Right.", "start": 0, "end": 300}]}
            """)
            guard case .segment(let segment)? = emissions.last else {
                Issue.record("no segment for \(label)")
                continue
            }
            #expect(segment.speaker == nil, "\(label)")
        }
    }

    @Test func assemblyAISpeakerRevisionIsForwarded() async throws {
        let replay = try await replay(
            adapter: AssemblyAIAdapter(
                apiKey: Self.key, model: "universal-3-6-pro", speakerLabels: true, formatTurns: false
            ),
            fixture: "assemblyai_diarized",
            chunks: [chunk()]
        )

        #expect(replay.sink.revisions == [[
            SpeakerRevision(
                turnOrder: 0,
                speaker: "B",
                words: [
                    TranscriptWord(text: "Hello", start: 0.5, end: 0.82),
                    TranscriptWord(text: "there.", start: 0.82, end: 1.1),
                ]
            ),
        ]])
    }

    @Test func assemblyAIEndMessageIsTerminate() throws {
        let adapter = AssemblyAIAdapter(apiKey: Self.key)

        #expect(try adapter.endMessages().map { try json($0) } == [.object(["type": .string("Terminate")])])
    }

    @Test func assemblyAITerminationCompletes() throws {
        let adapter = AssemblyAIAdapter(apiKey: Self.key)
        var emitter = AdapterEmitter()

        let complete = try adapter.handle(
            .text(#"{"type": "Termination", "audio_duration_seconds": 13, "session_duration_seconds": 14}"#),
            emit: &emitter
        )

        #expect(complete)
        #expect(emitter.emissions.isEmpty)
    }

    @Test func assemblyAIErrorMessageFails() async {
        let replay = await replayFailure(
            adapter: AssemblyAIAdapter(apiKey: Self.key),
            script: FixtureScript(steps: [
                .server(#"{"type": "Error", "error_code": 3005, "error": "Session Cancelled: An error occurred"}"#),
            ])
        )

        #expect(replay.result.ok == false)
        #expect(replay.sink.errors.count == 1)
        #expect(throws: CloudAdapterError.self) {
            try self.emissions(AssemblyAIAdapter(apiKey: Self.key), #"{"error": "Invalid Message Type: Foo"}"#)
        }
    }

    @Test func assemblyAIRequiresHundredMillisecondChunks() {
        #expect(AssemblyAIAdapter(apiKey: Self.key).minimumChunkSeconds == 0.1)
        #expect(AssemblyAIAdapter(apiKey: Self.key).targetRate == 16000)
    }

    /// The provider closes a session on a chunk under 20 ms (close 3007), which the
    /// remainder flushed before `Terminate` can be.
    @Test func assemblyAIPadsAChunkUnderTwentyMillisecondsWithSilence() {
        let adapter = AssemblyAIAdapter(apiKey: Self.key)
        let short = Data(repeating: 0x7F, count: 100)
        let full = Data(repeating: 0x7F, count: 3200)

        #expect(adapter.encodeChunk(short) == .binary(short + Data(count: 540)))
        #expect(adapter.encodeChunk(full) == .binary(full))
    }

    // MARK: - Shared configuration

    @Test func drainConfig() {
        #expect(OpenAIRealtimeAdapter(apiKey: Self.key).drainAfterComplete == .milliseconds(200))
        #expect(ElevenLabsAdapter(apiKey: Self.key).drainAfterComplete == .milliseconds(200))
        // `EndOfTranscript` is a hard terminal: nothing follows it.
        #expect(SpeechmaticsAdapter(apiKey: Self.key).drainAfterComplete == .zero)
        #expect(AssemblyAIAdapter(apiKey: Self.key).drainAfterComplete == .milliseconds(200))

        #expect(OpenAIRealtimeAdapter(apiKey: Self.key).targetRate == 24000)
        #expect(ElevenLabsAdapter(apiKey: Self.key).targetRate == 16000)
        #expect(SpeechmaticsAdapter(apiKey: Self.key).targetRate == 16000)
    }

    // MARK: - Harness

    private struct Replay {
        let result: StreamResult
        let sink: RecordingSink
        let connection: FakeWebSocketConnection
    }

    private static let gateSeconds: TimeInterval = 1

    private func chunk() -> [Float] { SignalFixtures.ramp(count: 4800, from: -0.5, to: 0.5) }

    private func started<Adapter: EngineAdapter>(
        _ adapter: Adapter,
        _ script: FixtureScript,
        _ clock: VirtualClock
    ) -> (engine: WebSocketEngine<Adapter>, connection: FakeWebSocketConnection, sink: RecordingSink) {
        let connection = FakeWebSocketConnection(script: script, clock: clock)
        let engine = WebSocketEngine(adapter: adapter, clock: clock) { connection }
        let sink = RecordingSink()
        engine.start(sink: sink)
        return (engine, connection, sink)
    }

    /// Replays a provider fixture on a `VirtualClock` and returns the finished session.
    private func replay<Adapter: EngineAdapter>(
        adapter: Adapter,
        fixture: String,
        chunks: [[Float]] = [],
        rate: Double = 48000
    ) async throws -> Replay {
        let url = try #require(
            Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures/streaming")
        )
        let clock = VirtualClock()
        let session = started(adapter, gated(try FixtureScript.load(Data(contentsOf: url))), clock)
        for chunk in chunks { session.engine.feed(PCMBufferFactory.make(samples: chunk, sampleRate: rate)) }

        await clock.waitUntilSleeping()  // the receive loop is parked at the gate
        let finishing = Task { await session.engine.finish(timeout: .seconds(5)) }
        await clock.waitUntilSleeping(count: 2)  // ... and the 5 s finish timeout joins it
        clock.advance(by: Self.gateSeconds)
        if adapter.drainAfterComplete > .zero {
            await clock.waitUntilSleeping(count: 2)  // the drain window, timeout still pending
            clock.advance(by: adapter.drainAfterComplete.seconds)
        }
        return Replay(result: await finishing.value, sink: session.sink, connection: session.connection)
    }

    /// Replays a script that fails instead of terminating: no gate, no drain window,
    /// so `finish` returns without time passing.
    private func replayFailure<Adapter: EngineAdapter>(
        adapter: Adapter,
        script: FixtureScript
    ) async -> Replay {
        let session = started(adapter, script, VirtualClock())
        return Replay(
            result: await session.engine.finish(timeout: .seconds(5)),
            sink: session.sink,
            connection: session.connection
        )
    }

    /// The fixtures are compressed transcripts: every server event scripted before the
    /// last `await_client` step belongs to the recording, ahead of the client's
    /// end-of-audio message. Parking the receive loop on the clock at that point states
    /// that ordering explicitly, for an engine that commits microseconds after `finish`.
    private func gated(_ script: FixtureScript) -> FixtureScript {
        var steps = script.steps
        let isGate = { (step: FixtureScript.Step) -> Bool in
            if case .awaitClient = step { return true }
            return false
        }
        guard let gate = steps.lastIndex(where: isGate) else { return script }
        steps.insert(.pause(.seconds(Self.gateSeconds)), at: gate)
        return FixtureScript(steps: steps)
    }

    private func json(_ message: WebSocketMessage?) throws -> JSONValue {
        guard case .text(let text)? = message else {
            throw HarnessError.notATextMessage
        }
        return try parse(text)
    }

    private func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// Scheme, host and path, without the query.
    private func endpoint(_ url: URL) throws -> String {
        var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.query = nil
        return try #require(components.string)
    }

    /// Every query parameter, decoded; a repeated name fails.
    private func query(_ url: URL) throws -> [String: String] {
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return try Dictionary(items.map { ($0.name, try #require($0.value)) }) { _, _ in
            throw HarnessError.repeatedQueryParameter
        }
    }

    /// `StartRecognition`'s `transcription_config`.
    private func transcriptionConfig(_ adapter: SpeechmaticsAdapter) throws -> [String: JSONValue] {
        guard case .object(let start) = try json(adapter.openMessages().first),
              case .object(let config)? = start["transcription_config"]
        else { throw HarnessError.missingTranscriptionConfig }
        return config
    }

    /// What one server message makes the adapter emit, outside any engine.
    private func emissions<Adapter: EngineAdapter>(
        _ adapter: Adapter,
        _ message: String
    ) throws -> [AdapterEmitter.Emission] {
        var adapter = adapter
        var emitter = AdapterEmitter()
        _ = try adapter.handle(.text(message), emit: &emitter)
        return emitter.emissions
    }

    /// One `AddTranscript` from a diarized session, in the vendor's documented shape.
    private static let diarizedTranscript = """
    {"message": "AddTranscript", "format": "2.9",
     "metadata": {"start_time": 0.5, "end_time": 1.1, "transcript": "Hello there. "},
     "results": [
       {"type": "word", "start_time": 0.5, "end_time": 0.82,
        "alternatives": [{"content": "Hello", "confidence": 0.98, "language": "en", "speaker": "S1"}]},
       {"type": "word", "start_time": 0.82, "end_time": 1.1,
        "alternatives": [{"content": "there", "confidence": 0.97, "language": "en", "speaker": "S1"}]},
       {"type": "punctuation", "start_time": 1.1, "end_time": 1.1, "attaches_to": "previous", "is_eos": true,
        "alternatives": [{"content": ".", "confidence": 1.0, "language": "en", "speaker": "S1"}]}]}
    """

    private enum HarnessError: Error { case notATextMessage, missingTranscriptionConfig, repeatedQueryParameter }
}
