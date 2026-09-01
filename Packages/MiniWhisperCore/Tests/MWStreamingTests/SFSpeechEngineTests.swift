import AVFAudio
import Foundation
import MWSupport
import MWTestSupport
import Testing

import MWStreaming

private struct RecogniserFailure: Error, CustomStringConvertible {
    let description = "kAFAssistantErrorDomain error 1101"
}

/// On-device recognition behind the `SpeechRecognitionAPI` seam, ported from
/// `../mini-whisper/tests/test_on_device.py` (10 cases).
@Suite struct SFSpeechEngineTests {
    // MARK: - Permission

    @Test(arguments: [
        (SpeechAuthorization.notDetermined, SpeechPermission.undetermined),
        (SpeechAuthorization.denied, SpeechPermission.denied),
        (SpeechAuthorization.restricted, SpeechPermission.denied),
        (SpeechAuthorization.authorized, SpeechPermission.authorized),
    ])
    func permissionStatusMapsAllFourValues(status: SpeechAuthorization, expected: SpeechPermission) {
        let api = FakeSpeechRecognitionAPI(status: status)

        #expect(SpeechPermission.ensureAuthorized(api: api) == expected)
    }

    @Test func requestOnlyWhenUndetermined() {
        let undetermined = FakeSpeechRecognitionAPI(status: .notDetermined)
        _ = SpeechPermission.ensureAuthorized(api: undetermined)
        #expect(undetermined.requestAuthorizationCalls == 1)

        for status in [SpeechAuthorization.denied, .restricted, .authorized] {
            let api = FakeSpeechRecognitionAPI(status: status)
            _ = SpeechPermission.ensureAuthorized(api: api)
            #expect(api.requestAuthorizationCalls == 0)
        }
    }

    // MARK: - Session

    @Test func requestSetsOnDeviceAndPartialResults() {
        let api = FakeSpeechRecognitionAPI()

        _ = started(api)

        #expect(api.startOptions == [
            RecognitionOptions(requiresOnDeviceRecognition: true, shouldReportPartialResults: true),
        ])
    }

    @Test func feedForwardsBuffersToRequest() {
        let api = FakeSpeechRecognitionAPI()
        let session = started(api)
        let buffer = PCMBufferFactory.make(samples: [0, 0.1, 0.2], sampleRate: 48000)

        session.engine.feed(buffer)

        #expect(api.request.appended.count == 1)
        #expect(api.request.appended.first === buffer)
    }

    @Test func feedBeforeStartBuffersAndFlushesOnStart() {
        let api = FakeSpeechRecognitionAPI()
        let engine = SFSpeechEngine(api: api, clock: VirtualClock())
        let first = PCMBufferFactory.make(samples: [0.1], sampleRate: 48000)
        let second = PCMBufferFactory.make(samples: [0.2], sampleRate: 48000)

        engine.feed(first)
        engine.feed(second)
        #expect(api.request.appended.isEmpty)

        engine.start(sink: RecordingSink())

        #expect(api.request.appended.count == 2)
        #expect(api.request.appended.first === first)
        #expect(api.request.appended.last === second)
    }

    @Test func bufferArrivingDuringFlushKeepsFeedOrder() {
        let api = FakeSpeechRecognitionAPI()
        let engine = SFSpeechEngine(api: api, clock: VirtualClock())
        let first = PCMBufferFactory.make(samples: [0.1], sampleRate: 48000)
        let second = PCMBufferFactory.make(samples: [0.2], sampleRate: 48000)
        let late = PCMBufferFactory.make(samples: [0.3], sampleRate: 48000)

        engine.feed(first)
        engine.feed(second)
        // The tap thread keeps delivering while `start` drains the backlog.
        api.request.onFirstAppend { engine.feed(late) }

        engine.start(sink: RecordingSink())

        #expect(api.request.appended.map { $0 === first } == [true, false, false])
        #expect(api.request.appended.map { $0 === second } == [false, true, false])
        #expect(api.request.appended.map { $0 === late } == [false, false, true])
    }

    @Test func partialAndFinalDriveSinkAndAssembler() async {
        let api = FakeSpeechRecognitionAPI()
        let session = started(api)

        api.deliver(.transcript("hello", isFinal: false))
        api.deliver(.transcript("hello world", isFinal: false))
        api.deliver(.transcript("hello world.", isFinal: true))

        #expect(session.sink.partials == ["hello", "hello world"])
        #expect(session.sink.finals == ["hello world."])
        #expect(await session.engine.finish(timeout: .seconds(5)).text == "hello world.")
    }

    // MARK: - Finish

    @Test func finishEndsAudioAndReturnsCompoundText() async {
        let api = FakeSpeechRecognitionAPI()
        let session = started(api)
        api.deliver(.transcript("hello world.", isFinal: true))

        let result = await session.engine.finish(timeout: .seconds(5))

        #expect(api.request.endAudioCalls == 1)
        #expect(result.ok)
        #expect(result.text == "hello world.")
    }

    @Test func finishTimesOutWithoutFinal() async {
        let clock = VirtualClock()
        let session = started(clock: clock)

        let finishing = Task { await session.engine.finish(timeout: .seconds(5)) }
        await clock.waitUntilSleeping()
        clock.advance(by: 5)
        let result = await finishing.value

        #expect(result.ok == false)
        #expect(result.text == "")
    }

    @Test func recogniserErrorFailsEngineOnce() async {
        let api = FakeSpeechRecognitionAPI()
        let session = started(api)

        api.deliver(.failure(AnyError(RecogniserFailure())))
        api.deliver(.failure(AnyError(RecogniserFailure())))

        #expect(session.sink.errors.count == 1)
        #expect(await session.engine.finish(timeout: .seconds(5)).ok == false)
    }

    @Test func unavailableAtStartFailsEngine() async {
        let api = FakeSpeechRecognitionAPI(startError: SpeechRecognitionError.recognizerUnavailable)
        let session = started(api)

        #expect(session.sink.errors.count == 1)
        #expect(api.request.endAudioCalls == 0)
        #expect(await session.engine.finish(timeout: .seconds(5)).ok == false)
    }

    @Test func usageReportsSecondsAndZeroTokens() async {
        let clock = VirtualClock()
        let api = FakeSpeechRecognitionAPI()
        let session = started(api, clock: clock)

        clock.advance(by: 2.5)
        api.deliver(.transcript("done", isFinal: true))

        #expect(await session.engine.finish(timeout: .seconds(5)).usage
            == StreamUsage(inputTokens: 0, outputTokens: 0, seconds: 2.5))
    }

    // MARK: - Shared fixtures

    @Test func wavFixturesAreBundled() throws {
        for name in ["filler_words", "self_corrections", "filler_and_corrections"] {
            let data = try Data(contentsOf: TestFixtures.wav(name))
            #expect(data.count > 44)
            #expect(data.prefix(4) == Data("RIFF".utf8))
            #expect(data.dropFirst(8).prefix(4) == Data("WAVE".utf8))
        }
    }

    // MARK: - Harness

    private func started(
        _ api: FakeSpeechRecognitionAPI = FakeSpeechRecognitionAPI(),
        clock: VirtualClock = VirtualClock()
    ) -> (engine: SFSpeechEngine, sink: RecordingSink) {
        let engine = SFSpeechEngine(api: api, clock: clock)
        let sink = RecordingSink()
        engine.start(sink: sink)
        return (engine, sink)
    }
}
