import AVFAudio
import Foundation
import MWAudio
import MWSupport
import MWTestSupport
import Testing

import MWStreaming

private enum TestConnectError: Error { case refused }

/// Skeleton behaviour ported from `../mini-whisper-py/tests/test_websocket_engines.py`
/// (cases 169–260); the three adapters land in Stage 11.
@Suite struct WebSocketEngineTests {
    private func buffer(_ samples: [Float], rate: Double = 48000) -> AVAudioPCMBuffer {
        PCMBufferFactory.make(samples: samples, sampleRate: rate)
    }

    private func engine(
        adapter: TestAdapter = TestAdapter(),
        clock: VirtualClock,
        connect: @escaping @Sendable () async throws -> any WebSocketConnection
    ) -> WebSocketEngine<TestAdapter> {
        WebSocketEngine(adapter: adapter, clock: clock, connect: connect)
    }

    @Test func feedBeforeOpenBuffersAndFlushesOnOpen() async throws {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(
            script: FixtureScript(steps: [
                .awaitClient(.type("open")),
                .awaitClient(.type("end")),
                .server(#"{"type":"complete"}"#),
            ]),
            clock: clock
        )
        let engine = engine(adapter: TestAdapter(targetRate: 24000), clock: clock) {
            try await clock.sleep(for: .seconds(10))
            return connection
        }
        let sink = RecordingSink()
        engine.start(sink: sink)
        await clock.waitUntilSleeping()

        let first = SignalFixtures.ramp(count: 4800, from: -0.5, to: 0.5)
        let second = SignalFixtures.ramp(count: 4800, from: 0.5, to: -0.5)
        engine.feed(buffer(first))
        engine.feed(buffer(second))
        #expect(connection.sentMessages.isEmpty)

        clock.advance(by: 10)
        let result = await engine.finish(timeout: .seconds(5))

        #expect(result.ok)
        #expect(connection.sentTypes == ["open", "__binary__", "__binary__", "end"])
        var converter = PCMConverter(from: 48000, to: 24000)
        #expect(connection.binaryPayloads == [converter.convert(first), converter.convert(second)])
    }

    @Test func preconnectBufferCappedAt60sThenFails() async throws {
        let clock = VirtualClock()
        let engine = engine(clock: clock) {
            try await clock.sleep(for: .seconds(3600))
            return FakeWebSocketConnection(script: FixtureScript(steps: []), clock: clock)
        }
        let sink = RecordingSink()
        engine.start(sink: sink)
        await clock.waitUntilSleeping()

        // One second of audio per buffer at 8 kHz.
        let oneSecond = [Float](repeating: 0, count: 8000)
        for _ in 0..<60 { engine.feed(buffer(oneSecond, rate: 8000)) }
        #expect(sink.errors.isEmpty)
        engine.feed(buffer(oneSecond, rate: 8000))
        #expect(sink.errors.count == 1)

        let result = await engine.finish(timeout: .seconds(5))
        #expect(result.ok == false)
    }

    @Test func connectFailureReportsErrorOnceAndFinishFailsFast() async {
        let clock = VirtualClock()
        let engine = engine(clock: clock) { throw TestConnectError.refused }
        let sink = RecordingSink()
        engine.start(sink: sink)

        // The clock is never advanced, so a timeout would hang: returning at all
        // proves `finish` took the failure path.
        let result = await engine.finish(timeout: .seconds(5))

        #expect(result.ok == false)
        #expect(sink.errors.count == 1)
    }

    @Test func socketErrorReportsErrorOnce() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(
            script: FixtureScript(steps: [.awaitClient(.type("open")), .serverError("boom")]),
            clock: clock
        )
        let engine = engine(clock: clock) { connection }
        let sink = RecordingSink()
        engine.start(sink: sink)

        let result = await engine.finish(timeout: .seconds(5))

        #expect(result.ok == false)
        #expect(sink.errors.count == 1)
    }

    @Test func finishTimeoutReturnsNotOk() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(
            script: FixtureScript(steps: [.awaitClient(.type("open"))]),
            clock: clock
        )
        let engine = engine(clock: clock) { connection }
        engine.start(sink: RecordingSink())

        let finishing = Task { await engine.finish(timeout: .seconds(5)) }
        await clock.waitUntilSleeping()
        clock.advance(by: 5)
        let result = await finishing.value

        #expect(result.ok == false)
        #expect(result.text == "")
    }

    @Test func terminalBeforeEndOfAudioDoesNotComplete() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(
            script: FixtureScript(steps: [
                .awaitClient(.type("open")),
                // Server-VAD completion mid-stream: terminal, but not ours yet.
                .server(#"{"type":"complete"}"#),
                // Parks the receive loop, so the early terminal is provably handled
                // before `finish` puts the end message on the wire.
                .pause(.seconds(1)),
                .awaitClient(.type("end")),
                .server(#"{"type":"final","text":"hello"}"#),
                .server(#"{"type":"complete"}"#),
            ]),
            clock: clock
        )
        let engine = engine(clock: clock) { connection }
        let sink = RecordingSink()
        engine.start(sink: sink)
        await clock.waitUntilSleeping()

        let finishing = Task { await engine.finish(timeout: .seconds(5)) }
        await clock.waitUntilSleeping(count: 2)
        clock.advance(by: 1)
        let result = await finishing.value

        #expect(result.ok)
        #expect(result.text == "hello")
        #expect(sink.finals == ["hello"])
    }

    @Test func drainScoopsTrailingEvents() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(script: trailingEventScript(), clock: clock)
        let engine = engine(
            adapter: TestAdapter(drainAfterComplete: .milliseconds(200)),
            clock: clock
        ) { connection }
        let sink = RecordingSink()
        engine.start(sink: sink)

        let finishing = Task { await engine.finish(timeout: .seconds(5)) }
        await clock.waitUntilSleeping(count: 2)
        clock.advance(by: 0.2)
        let result = await finishing.value

        #expect(result.ok)
        #expect(result.text == "hello trailing")
        #expect(sink.finals == ["hello", "trailing"])
    }

    @Test func noDrainWhenZero() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(script: trailingEventScript(), clock: clock)
        let engine = engine(clock: clock) { connection }
        let sink = RecordingSink()
        engine.start(sink: sink)

        let result = await engine.finish(timeout: .seconds(5))

        #expect(result.ok)
        #expect(result.text == "hello")
        #expect(sink.finals == ["hello"])
    }

    @Test func usageSecondsEqualFedSeconds() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(
            script: FixtureScript(steps: [
                .awaitClient(.type("open")),
                .awaitClient(.type("end")),
                .server(#"{"type":"complete","input_tokens":12,"output_tokens":4}"#),
            ]),
            clock: clock
        )
        let engine = engine(clock: clock) { connection }
        engine.start(sink: RecordingSink())
        engine.feed(buffer([Float](repeating: 0, count: 4800)))
        engine.feed(buffer([Float](repeating: 0, count: 2400)))

        let result = await engine.finish(timeout: .seconds(5))

        #expect(abs(result.usage.seconds - 0.15) < 1e-9)
        #expect(result.usage.inputTokens == 12)
        #expect(result.usage.outputTokens == 4)
    }

    @Test func chunksAreConvertedToTargetRate() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(
            script: FixtureScript(steps: [
                .awaitClient(.type("open")),
                .awaitClient(.type("end")),
                .server(#"{"type":"complete"}"#),
            ]),
            clock: clock
        )
        let engine = engine(adapter: TestAdapter(targetRate: 24000), clock: clock) { connection }
        engine.start(sink: RecordingSink())

        let chunk = SignalFixtures.sine(count: 4410, sampleRate: 44100)
        engine.feed(buffer(chunk, rate: 44100))
        _ = await engine.finish(timeout: .seconds(5))

        var converter = PCMConverter(from: 44100, to: 24000)
        #expect(connection.binaryPayloads == [converter.convert(chunk)])
    }

    @Test func streamingFixturesLoadFromTestBundle() throws {
        for name in ["openai_realtime", "elevenlabs", "speechmatics"] {
            let url = try #require(
                Bundle.module.url(
                    forResource: name,
                    withExtension: "json",
                    subdirectory: "Fixtures/streaming"
                )
            )
            let script = try FixtureScript.load(Data(contentsOf: url))
            #expect(script.steps.isEmpty == false)
        }
    }

    @Test func segmentReachesTheSinkButNotTheAssembler() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(
            script: completingScript(serving: [
                #"{"type":"final","text":"a b"}"#,
                #"{"type":"segment","text":"a b","speaker":"S1"}"#,
            ]),
            clock: clock
        )
        let engine = engine(clock: clock) { connection }
        let sink = RecordingSink()
        engine.start(sink: sink)

        let result = await engine.finish(timeout: .seconds(5))

        #expect(result.text == "a b")
        #expect(sink.finals == ["a b"])
        #expect(sink.segments == [TranscriptSegment(text: "a b", speaker: "S1", start: 0, end: 0)])
    }

    @Test func speakerRevisionReachesTheSink() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(
            script: completingScript(serving: [#"{"type":"revision","turn_order":2,"speaker":"B"}"#]),
            clock: clock
        )
        let engine = engine(clock: clock) { connection }
        let sink = RecordingSink()
        engine.start(sink: sink)

        let result = await engine.finish(timeout: .seconds(5))

        #expect(result.text == "")
        #expect(sink.revisions == [[SpeakerRevision(turnOrder: 2, speaker: "B")]])
    }

    @Test func sessionLimitReachesTheSink() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(
            script: completingScript(serving: [
                #"{"type":"limit","expires_at":1700000000}"#,
                #"{"type":"limit"}"#,
            ]),
            clock: clock
        )
        let engine = engine(clock: clock) { connection }
        let sink = RecordingSink()
        engine.start(sink: sink)

        let result = await engine.finish(timeout: .seconds(5))

        #expect(result.text == "")
        #expect(sink.limits == [.expiresAt(Date(timeIntervalSince1970: 1_700_000_000)), .warning])
    }

    @Test func serverCloseSurfacesItsCode() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(
            script: FixtureScript(steps: [
                .awaitClient(.type("open")),
                .serverClose(code: 4005, reason: "quota"),
            ]),
            clock: clock
        )
        let engine = engine(clock: clock) { connection }
        let sink = RecordingSink()
        engine.start(sink: sink)

        let result = await engine.finish(timeout: .seconds(5))

        #expect(result.ok == false)
        #expect(sink.errors.count == 1)
        #expect(sink.errors.first.map { AnyError($0).description.contains("4005") } == true)
    }

    @Test func serverCloseLoadsFromJSON() throws {
        let json = #"{"steps":[{"server_close":{"code":4005,"reason":"quota"}}]}"#
        let script = try FixtureScript.load(Data(json.utf8))
        guard case .serverClose(let code, let reason)? = script.steps.first else {
            Issue.record("expected a server_close step")
            return
        }
        #expect(code == 4005)
        #expect(reason == "quota")
    }

    @Test func accumulatesToTheAdaptersMinimumChunk() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(script: completingScript(), clock: clock)
        let engine = engine(adapter: TestAdapter(minimumChunkSeconds: 0.1), clock: clock) { connection }
        engine.start(sink: RecordingSink())

        let chunks = (0..<5).map { _ in SignalFixtures.sine(count: 960, sampleRate: 48000) }
        for chunk in chunks { engine.feed(buffer(chunk)) }
        _ = await engine.finish(timeout: .seconds(5))

        var converter = PCMConverter(from: 48000, to: 16000)
        #expect(connection.sentTypes == ["open", "__binary__", "end"])
        #expect(connection.binaryPayloads == [converter.convert(chunks.flatMap { $0 })])
        #expect(connection.binaryPayloads.map(\.count) == [3200])
    }

    @Test func flushesTheRemainderBeforeEnd() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(script: completingScript(), clock: clock)
        let engine = engine(adapter: TestAdapter(minimumChunkSeconds: 0.1), clock: clock) { connection }
        engine.start(sink: RecordingSink())

        for _ in 0..<7 { engine.feed(buffer(SignalFixtures.sine(count: 960, sampleRate: 48000))) }
        _ = await engine.finish(timeout: .seconds(5))

        #expect(connection.sentTypes == ["open", "__binary__", "__binary__", "end"])
        #expect(connection.binaryPayloads.map(\.count) == [3200, 1280])
    }

    @Test func noMinimumChunkKeepsOneMessagePerBuffer() async {
        let clock = VirtualClock()
        let connection = FakeWebSocketConnection(script: completingScript(), clock: clock)
        let engine = engine(clock: clock) { connection }
        engine.start(sink: RecordingSink())

        for _ in 0..<3 { engine.feed(buffer(SignalFixtures.sine(count: 960, sampleRate: 48000))) }
        _ = await engine.finish(timeout: .seconds(5))

        #expect(connection.binaryPayloads.map(\.count) == [640, 640, 640])
    }

    /// Open, end of audio, the given server events, then the terminal event.
    private func completingScript(serving events: [String] = []) -> FixtureScript {
        FixtureScript(
            steps: [.awaitClient(.type("open")), .awaitClient(.type("end"))]
                + events.map(FixtureScript.Step.server)
                + [.server(#"{"type":"complete"}"#)]
        )
    }

    private func trailingEventScript() -> FixtureScript {
        FixtureScript(steps: [
            .awaitClient(.type("open")),
            .awaitClient(.type("end")),
            .server(#"{"type":"final","text":"hello"}"#),
            .server(#"{"type":"complete"}"#),
            .server(#"{"type":"final","text":"trailing"}"#),
        ])
    }
}
