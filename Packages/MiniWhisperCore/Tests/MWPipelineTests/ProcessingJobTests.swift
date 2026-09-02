import Foundation
import MWAudio
import MWConfig
import MWHistory
import MWProfiles
import MWHotkeys
import MWPaste
import MWStreaming
import MWSupport
import MWTestSupport
import MWTranscription
import MWUsage
import Testing

import MWPipeline

/// The processing half of the state machine (F12–F15, F21, F26, F28, F29, F35), a port of
/// `Controller._process` in `../mini-whisper/src/mini_whisper/controller.py` and its tests.
@Suite struct ProcessingJobTests {
    // MARK: - Fixtures

    private static let target = PasteTarget(
        pid: 4242, name: "Slack", bundleID: "com.tinyspeck.slackmacgap"
    )
    private static let recording = Recording(wav: Data("fake wav".utf8), duration: 1, meanRMS: 0.02)
    private static let transcribeBase = "Transcribe base."
    private static let cleanupBase = "Clean up."

    private static func profile(
        cleanupEnabled: Bool = true,
        submitKey: SubmitKey = .enter
    ) -> ResolvedProfile {
        ResolvedProfile(
            name: "Default",
            cleanupEnabled: cleanupEnabled,
            submitKey: submitKey,
            cleanupPrompt: cleanupBase,
            isDefault: true
        )
    }

    private static func config(cleanupEnabled: Bool = true, vocabulary: [String] = []) -> Config {
        var config = Config()
        config.cleanupEnabled = cleanupEnabled
        config.vocabulary = vocabulary
        return config
    }

    private static func engine(
        _ name: EngineName = .onDevice,
        text: String = "streamed text",
        ok: Bool = true,
        seconds: TimeInterval = 3
    ) -> FakeStreamingEngine {
        FakeStreamingEngine(
            name: name,
            result: StreamResult(text: text, ok: ok, usage: StreamUsage(seconds: seconds))
        )
    }

    private struct StubPrompts: PromptProviding {
        func transcribeInstructions() throws -> String { ProcessingJobTests.transcribeBase }
    }

    private struct LocalisedFailure: LocalizedError {
        let errorDescription: String?
    }

    /// Flips to stale from inside a fake, so a test can put the generation bump between
    /// two specific checkpoints.
    private final class Staleness: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var isStale: @Sendable () -> Bool { { [self] in lock.withLock { value } } }
        func makeStale() { lock.withLock { value = true } }
    }

    private struct StalingTranscriber: Transcriber {
        let staleness: Staleness

        func transcribe(wav: Data, instructions: String) async throws -> (String, TokenUsage) {
            staleness.makeStale()
            return ("hello world", TokenUsage())
        }
    }

    private struct StalingCleaner: Cleaner {
        let staleness: Staleness

        func clean(_ text: String, prompt: String) async throws -> (String, TokenUsage) {
            staleness.makeStale()
            return ("Hello world.", TokenUsage())
        }
    }

    // MARK: - Harness

    private final class Harness {
        let recorder = UIEventRecorder()
        let sounds = FakeSoundPlayer()
        let usage: FakeUsageStore
        let history = FakeHistoryStore()
        let secrets: FakeSecretStore
        let transcriber: FakeTranscriber
        let cleaner: FakeCleaner
        let paster: FakePaster
        let job: ProcessingJob

        init(
            key: String? = "sk-test",
            transcriber: FakeTranscriber = FakeTranscriber(
                text: "hello world", usage: TokenUsage(inputTokens: 10)
            ),
            cleaner: FakeCleaner = FakeCleaner(
                text: "Hello world.", usage: TokenUsage(inputTokens: 5, outputTokens: 8)
            ),
            paster: FakePaster = FakePaster(),
            usage: FakeUsageStore = FakeUsageStore(),
            transcriberOverride: (any Transcriber)? = nil,
            cleanerOverride: (any Cleaner)? = nil
        ) {
            self.transcriber = transcriber
            self.cleaner = cleaner
            self.paster = paster
            self.usage = usage
            secrets = FakeSecretStore(key.map { [.openai: $0] } ?? [:])
            job = ProcessingJob(deps: Dependencies(
                transcriber: transcriberOverride ?? transcriber,
                cleaner: cleanerOverride ?? cleaner,
                paster: paster,
                secrets: secrets,
                usage: usage,
                history: history,
                sounds: sounds,
                prompts: StubPrompts()
            ))
        }

        func run(
            engine: FakeStreamingEngine? = nil,
            sink: StreamSink? = nil,
            profile: ResolvedProfile = ProcessingJobTests.profile(),
            binding: BindingName = .paste,
            config: Config = ProcessingJobTests.config(),
            isStale: @escaping @Sendable () -> Bool = { false }
        ) async {
            await job.run(
                ProcessingInput(
                    recording: ProcessingJobTests.recording,
                    engine: engine,
                    sink: sink,
                    profile: profile,
                    target: ProcessingJobTests.target,
                    binding: binding,
                    config: config
                ),
                isStale: isStale,
                emit: recorder.emit
            )
        }

        func makeSink() -> StreamSink { StreamSink(emit: recorder.emit) }
    }

    // MARK: - Streamed vs batch (F12, F21)

    @Test func streamedTranscriptUsedWhenOkNonEmptyAndNotFailed() async {
        let harness = Harness()

        await harness.run(engine: Self.engine(), sink: harness.makeSink())

        #expect(harness.transcriber.calls.isEmpty)
        #expect(harness.cleaner.calls.map(\.text) == ["streamed text"])
        #expect(harness.paster.pasted == ["Hello world."])
        #expect(!harness.recorder.events.contains(.captionUnavailable))
    }

    @Test func finishNotOkFallsBackToBatch() async {
        let harness = Harness()

        await harness.run(engine: Self.engine(text: "", ok: false, seconds: 2), sink: harness.makeSink())

        #expect(harness.transcriber.calls.count == 1)
        #expect(harness.paster.pasted == ["Hello world."])
        #expect(harness.recorder.events.filter { $0 == .captionUnavailable }.count == 1)
    }

    @Test func emptyCompoundFallsBackToBatch() async {
        let harness = Harness()

        await harness.run(engine: Self.engine(text: "   ", seconds: 2), sink: harness.makeSink())

        #expect(harness.transcriber.calls.count == 1)
        #expect(harness.recorder.events.contains(.captionUnavailable))
    }

    @Test func sinkFailedFallsBackToBatch() async {
        let harness = Harness()
        let sink = harness.makeSink()
        sink.onEngineError(LocalisedFailure(errorDescription: "socket dropped"))

        await harness.run(engine: Self.engine(), sink: sink)

        #expect(harness.transcriber.calls.count == 1)
        #expect(harness.paster.pasted == ["Hello world."])
        #expect(harness.recorder.events.filter { $0 == .captionUnavailable }.count == 1)
    }

    @Test func finishTimeoutIs5s() async {
        let harness = Harness()
        let engine = Self.engine()

        await harness.run(engine: engine, sink: harness.makeSink())

        #expect(engine.finishTimeout == .seconds(5))
    }

    // MARK: - No OpenAI key (F13)

    @Test func noKeyWithStreamedTextPastesRawWithoutCleanup() async {
        let harness = Harness(key: nil)

        await harness.run(engine: Self.engine(), sink: harness.makeSink())

        #expect(harness.transcriber.calls.isEmpty)
        #expect(harness.cleaner.calls.isEmpty)
        #expect(harness.paster.pasted == ["streamed text"])
    }

    @Test func noKeyWithoutStreamedTextEmitsNoAPIKeyError() async {
        let harness = Harness(key: nil)

        await harness.run(
            engine: Self.engine(.openai, text: "", ok: false, seconds: 3),
            sink: harness.makeSink()
        )

        #expect(harness.recorder.events.contains(.error("No API key configured")))
        #expect(harness.transcriber.calls.isEmpty)
        #expect(harness.paster.calls.isEmpty)
        #expect(harness.usage.added == [
            ProviderUsage(streamedSeconds: ["openai": 3], costUSD: 0.00085),
        ])
    }

    // MARK: - Empty transcript

    @Test func emptyBatchTextPlaysOffHidesPastesNothing() async {
        let harness = Harness(transcriber: FakeTranscriber(text: "   "))

        await harness.run(engine: Self.engine(.openai, text: "", ok: false, seconds: 3), sink: harness.makeSink())

        #expect(harness.paster.calls.isEmpty)
        #expect(harness.sounds.played == [.off])
        #expect(harness.recorder.events.contains(.idle))
        #expect(harness.usage.added == [
            ProviderUsage(streamedSeconds: ["openai": 3], costUSD: 0.00085),
        ])
    }

    // MARK: - Cleanup (F26) and vocabulary (F28)

    @Test func cleanupRunsWhenEffective() async {
        let harness = Harness()

        await harness.run()

        #expect(harness.cleaner.calls.map(\.text) == ["hello world"])
        #expect(harness.cleaner.calls.map(\.prompt) == [Self.cleanupBase])
        #expect(harness.paster.pasted == ["Hello world."])
    }

    @Test func cleanupSkippedWhenIneffective() async {
        let harness = Harness()

        await harness.run(config: Self.config(cleanupEnabled: false))

        #expect(harness.cleaner.calls.isEmpty)
        #expect(harness.paster.pasted == ["hello world"])
    }

    @Test func vocabularyReachesBothPrompts() async {
        let harness = Harness()

        await harness.run(config: Self.config(vocabulary: ["Mini Whisper", "xcodegen"]))

        #expect(harness.transcriber.calls.map(\.instructions) == [
            "Transcribe base.\n\nVocabulary (spell exactly as written): Mini Whisper, xcodegen",
        ])
        #expect(harness.cleaner.calls.map(\.prompt) == [
            "Clean up.\n\nPreserve these terms exactly as written: Mini Whisper, xcodegen",
        ])
    }

    // MARK: - Generation guard (F15)

    @Test func staleBeforeBatchStopsAndBillsSecondsOnly() async {
        let harness = Harness()

        await harness.run(
            engine: Self.engine(.openai, text: "", ok: false, seconds: 3),
            sink: harness.makeSink(),
            isStale: { true }
        )

        #expect(harness.transcriber.calls.isEmpty)
        #expect(harness.paster.calls.isEmpty)
        #expect(harness.sounds.played == [.off])
        #expect(harness.recorder.events.contains(.idle))
        #expect(harness.usage.added == [
            ProviderUsage(streamedSeconds: ["openai": 3], costUSD: 0.00085),
        ])
    }

    @Test func staleBeforeCleanupStopsAndBillsSecondsOnly() async {
        let staleness = Staleness()
        let harness = Harness(transcriberOverride: StalingTranscriber(staleness: staleness))

        await harness.run(
            engine: Self.engine(.openai, text: "", ok: false, seconds: 3),
            sink: harness.makeSink(),
            isStale: staleness.isStale
        )

        #expect(harness.cleaner.calls.isEmpty)
        #expect(harness.paster.calls.isEmpty)
        #expect(harness.recorder.events.contains(.idle))
        #expect(harness.usage.added == [
            ProviderUsage(streamedSeconds: ["openai": 3], costUSD: 0.00085),
        ])
    }

    @Test func staleBeforePasteStopsAndBillsSecondsOnly() async {
        let staleness = Staleness()
        let harness = Harness(cleanerOverride: StalingCleaner(staleness: staleness))

        await harness.run(
            engine: Self.engine(.openai, seconds: 3),
            sink: harness.makeSink(),
            isStale: staleness.isStale
        )

        #expect(harness.paster.calls.isEmpty)
        #expect(harness.history.appended.isEmpty)
        #expect(harness.recorder.events.contains(.idle))
        #expect(!harness.recorder.events.contains(where: { if case .result = $0 { true } else { false } }))
        #expect(harness.usage.added == [
            ProviderUsage(streamedSeconds: ["openai": 3], costUSD: 0.00085),
        ])
    }

    // MARK: - Delivery, billing and history (F29, F35)

    @Test func deliveredDictationBillsTokensAndSecondsAndAppendsHistory() async {
        let harness = Harness()

        await harness.run(engine: Self.engine(.openai, seconds: 3), sink: harness.makeSink())

        #expect(harness.usage.added == [
            ProviderUsage(
                inputTokens: 5,
                outputTokens: 8,
                streamedSeconds: ["openai": 3],
                costUSD: 0.000856
            ),
        ])
        #expect(harness.history.appended.count == 1)
    }

    @Test func historyEntryFieldsMatchTarget() async {
        let harness = Harness()

        await harness.run(engine: Self.engine(.openai, seconds: 3), sink: harness.makeSink())

        let entry = harness.history.appended.first
        #expect(entry?.text == "Hello world.")
        #expect(entry?.appName == "Slack")
        #expect(entry?.bundleID == "com.tinyspeck.slackmacgap")
        #expect(entry?.engine == "openai")
        #expect(entry?.streamedSeconds == 3)
        #expect(entry?.costUSD == 0.000856)
    }

    @Test func pasteFailureEmitsErrorNoHistory() async {
        let harness = Harness(paster: FakePaster(failure: PasteError.targetGone))

        await harness.run()

        #expect(harness.history.appended.isEmpty)
        #expect(harness.recorder.events.contains(.error("Target app is no longer running")))
    }

    @Test func submitKeyOnlyForPasteSubmitBinding() async {
        let held = Harness()
        await held.run(profile: Self.profile(submitKey: .cmdEnter), binding: .paste)

        let submitted = Harness()
        await submitted.run(profile: Self.profile(submitKey: .cmdEnter), binding: .pasteSubmit)

        #expect(held.paster.calls.map(\.submit) == [nil])
        #expect(submitted.paster.calls.map(\.submit) == [.cmdEnter])
    }

    // MARK: - Errors (F14)

    @Test func http401Message() async {
        let harness = Harness(transcriber: FakeTranscriber(failure: APIError.httpStatus(401)))

        await harness.run()

        #expect(harness.recorder.events.contains(.error("Invalid API key — please update in Settings.")))
    }

    @Test func http429Message() async {
        let harness = Harness(transcriber: FakeTranscriber(failure: APIError.httpStatus(429)))

        await harness.run()

        #expect(harness.recorder.events.contains(.error("Rate limited — please wait and try again.")))
    }

    @Test func otherHTTPMessage() async {
        let harness = Harness(transcriber: FakeTranscriber(failure: APIError.httpStatus(503)))

        await harness.run()

        #expect(harness.recorder.events.contains(.error("API error (503).")))
    }

    @Test func genericErrorUsesDescription() async {
        let harness = Harness(
            cleaner: FakeCleaner(failure: LocalisedFailure(errorDescription: "network unreachable"))
        )

        await harness.run()

        #expect(harness.recorder.events.contains(.error("network unreachable")))
        #expect(harness.paster.calls.isEmpty)
    }

    @Test func errorsPlayOffSound() async {
        let harness = Harness(transcriber: FakeTranscriber(failure: APIError.httpStatus(401)))

        await harness.run()

        #expect(harness.sounds.played == [.off])
    }

    // MARK: - Usage rows (F31, F35)

    @Test func usageEventCarriesFormattedRows() async {
        let harness = Harness(
            transcriber: FakeTranscriber(text: "hello world"),
            usage: FakeUsageStore(
                today: DayEntry(
                    inputTokens: 1200,
                    outputTokens: 3400,
                    streamedSeconds: ["on_device": 720],
                    costUSD: 0.08
                ),
                monthCost: 1.42
            )
        )

        await harness.run(config: Self.config(cleanupEnabled: false))

        #expect(harness.recorder.events.suffix(2) == [
            .result("hello world"),
            .usage(today: "Today: 1.2k/3.4k tok · 12m · $0.08", month: "Month: $1.42"),
        ])
    }
}
