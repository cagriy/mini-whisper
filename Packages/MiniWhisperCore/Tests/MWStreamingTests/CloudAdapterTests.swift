import Foundation
import MWAudio
import MWConfig
import MWCorrections
import MWSupport
import MWTestSupport
import Testing

import MWStreaming

/// The three cloud adapters against the wire protocols pinned in design §5.4,
/// replayed through the fixture transcripts ported from
/// `../mini-whisper/tests/fixtures/streaming/` (Python `test_websocket_engines.py`
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

    // MARK: - Shared configuration

    @Test func drainConfig() {
        #expect(OpenAIRealtimeAdapter(apiKey: Self.key).drainAfterComplete == .milliseconds(200))
        #expect(ElevenLabsAdapter(apiKey: Self.key).drainAfterComplete == .milliseconds(200))
        // `EndOfTranscript` is a hard terminal: nothing follows it.
        #expect(SpeechmaticsAdapter(apiKey: Self.key).drainAfterComplete == .zero)

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

    private enum HarnessError: Error { case notATextMessage }
}
