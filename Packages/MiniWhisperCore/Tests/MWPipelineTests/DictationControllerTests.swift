import AVFAudio
import Foundation
import MWAudio
import MWConfig
import MWCorrections
import MWHotkeys
import MWPaste
import MWProfiles
import MWStreaming
import MWSupport
import MWTestSupport
import MWTranscription
import MWUsage
import Testing

@testable import MWPipeline

/// The main-actor state machine: press/release, hold vs toggle, the recording gate, engine
/// selection, the generation guard, idle stop, device changes and abort
/// (F9–F11, F15–F19, F23, N1) — a port of `Controller` in
/// `../mini-whisper-py/src/mini_whisper/controller.py`.
@MainActor
@Suite struct DictationControllerTests {
    // MARK: - Doubles

    private final class FakeFileWatcher: FileWatcher, @unchecked Sendable {
        func start(url: URL, onChange: @escaping @Sendable () -> Void) {}
        func stop() {}
    }

    private struct StubPrompts: PromptProviding {
        func transcribeInstructions() throws -> String { "Transcribe base." }
        func cleanupPrompt() throws -> String { "Clean up." }
    }

    private struct StubFailure: LocalizedError {
        let errorDescription: String?
    }

    /// Records every duration slept on, so `noPollingTimers` can prove the controller
    /// arms one-shots and never a repeating timer (N1).
    private final class RecordingClock: MWSupport.Clock, @unchecked Sendable {
        let base = VirtualClock()
        private let lock = NSLock()
        private var storage: [TimeInterval] = []

        var sleeps: [TimeInterval] { lock.withLock { storage } }
        var now: TimeInterval { base.now }

        func sleep(for duration: Duration) async throws {
            lock.withLock { storage.append(duration.seconds) }
            try await base.sleep(for: duration)
        }

        func advance(by seconds: TimeInterval) { base.advance(by: seconds) }
        func waitUntilSleeping(count: Int = 1) async { await base.waitUntilSleeping(count: count) }
    }

    /// Pulls from the controller's event stream off the main actor, so the harness can stay
    /// main-actor isolated while still iterating.
    private final class EventPuller: @unchecked Sendable {
        private var iterator: AsyncStream<UIEvent>.AsyncIterator

        init(_ stream: AsyncStream<UIEvent>) {
            iterator = stream.makeAsyncIterator()
        }

        func next() async -> UIEvent? { await iterator.next() }
    }

    /// Runs a hook inside the cleanup call, so a test can land a second press exactly while
    /// the job is in flight.
    private final class HookCleaner: Cleaner, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: (@Sendable () async -> Void)?

        var hook: (@Sendable () async -> Void)? {
            get { lock.withLock { storage } }
            set { lock.withLock { storage = newValue } }
        }

        func clean(_ text: String, prompt: String) async throws -> (String, TokenUsage) {
            await hook?()
            return ("Hello world.", TokenUsage())
        }
    }

    // MARK: - Harness

    @MainActor
    private final class Harness {
        let clock = RecordingClock()
        let audio = FakeAudioCapture()
        let engines = FakeEngineProvider()
        let frontmost = FakeFrontmostApp(DictationControllerTests.slack)
        let sounds = FakeSoundPlayer()
        let paster: FakePaster
        let usage = FakeUsageStore()
        let history = FakeHistoryStore()
        let secrets = FakeSecretStore([.openai: "sk-test"])
        let transcriber = FakeTranscriber(text: "hello world", usage: TokenUsage(inputTokens: 10))
        let cleaner: any Cleaner
        let directory: TempDirectory
        let store: ConfigStore
        let controller: DictationController

        private let puller: EventPuller

        init(
            paster: FakePaster = FakePaster(),
            cleaner: any Cleaner = FakeCleaner(
                text: "Hello world.", usage: TokenUsage(inputTokens: 5, outputTokens: 8)
            ),
            _ configure: @escaping @Sendable (inout Config) -> Void = { _ in }
        ) async throws {
            self.paster = paster
            self.cleaner = cleaner
            directory = try TempDirectory()
            store = ConfigStore(directory: directory.url, watcher: FakeFileWatcher())
            try await store.update(configure)
            controller = DictationController(
                deps: Dependencies(
                    audio: audio,
                    engines: engines,
                    frontmost: frontmost,
                    transcriber: transcriber,
                    cleaner: cleaner,
                    paster: paster,
                    secrets: secrets,
                    usage: usage,
                    history: history,
                    sounds: sounds,
                    prompts: StubPrompts()
                ),
                config: store,
                clock: clock
            )
            puller = EventPuller(controller.uiEvents)
        }

        func next() async -> UIEvent? { await puller.next() }

        func next(_ count: Int) async -> [UIEvent] {
            var events: [UIEvent] = []
            for _ in 0..<count {
                guard let event = await puller.next() else { break }
                events.append(event)
            }
            return events
        }

        /// Pulls events until `event` arrives, so a test can synchronise on a milestone
        /// rather than on a task handle.
        @discardableResult
        func waitFor(_ event: UIEvent) async -> [UIEvent] {
            var seen: [UIEvent] = []
            while let next = await puller.next() {
                seen.append(next)
                if next == event { break }
            }
            return seen
        }

        /// Lets a resumed timer task run to its next suspension before the test asserts.
        func drainTimers() async {
            await Task.yield()
            await Task.yield()
        }

        var idleStops: [Duration] {
            audio.calls.compactMap {
                if case .scheduleIdleStop(let duration) = $0 { duration } else { nil }
            }
        }

        func buffer(_ level: Float) -> AVAudioPCMBuffer {
            PCMBufferFactory.make(samples: [Float](repeating: level, count: 1024), sampleRate: 48000)
        }
    }

    nonisolated private static let slack = PasteTarget(
        pid: 4242, name: "Slack", bundleID: "com.tinyspeck.slackmacgap"
    )
    nonisolated private static let terminal = PasteTarget(
        pid: 99, name: "Terminal", bundleID: "com.apple.Terminal"
    )

    private static func openAIEngine(seconds: TimeInterval = 3) -> FakeStreamingEngine {
        FakeStreamingEngine(
            name: .openai,
            result: StreamResult(text: "streamed text", ok: true, usage: StreamUsage(seconds: seconds))
        )
    }

    private static let threeOpenAISeconds = ProviderUsage(
        streamedSeconds: ["openai": 3], costUSD: 0.00085
    )

    // MARK: - Press (F9, N1)

    @Test func pressEmitsStartingBeforeAnyAwait() async throws {
        let harness = try await Harness()
        harness.audio.blockCancelIdleStop()

        harness.controller.hotkeyPressed(.paste)

        #expect(await harness.next() == .starting)
        harness.audio.releaseCancelIdleStop()
        await harness.controller.settle()
    }

    @Test func pressCancelsIdleStopAndBeginsCapture() async throws {
        let harness = try await Harness()

        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        #expect(harness.audio.calls.prefix(2) == [.cancelIdleStop, .beginCapture])
    }

    @Test func firstBufferEmitsRecordingAndPlaysOn() async throws {
        let harness = try await Harness()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        harness.audio.send(.live)

        #expect(await harness.next(2) == [.starting, .recording])
        #expect(harness.sounds.played == [.on])
    }

    @Test func tickPlaysWhenNotLiveWithin100ms() async throws {
        let harness = try await Harness()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 0.1)
        await harness.drainTimers()
        #expect(harness.sounds.played == [.tick])

        harness.audio.send(.live)
        #expect(await harness.next(2) == [.starting, .recording])
        #expect(harness.sounds.played == [.tick, .on])
    }

    @Test func noTickWhenLiveBefore100ms() async throws {
        let harness = try await Harness()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        harness.audio.send(.live)
        #expect(await harness.next(2) == [.starting, .recording])

        harness.clock.advance(by: 0.5)
        await harness.drainTimers()

        #expect(harness.sounds.played == [.on])
    }

    @Test func levelEventPerBuffer() async throws {
        let harness = try await Harness()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        harness.audio.feed(harness.buffer(0.5))
        harness.audio.feed(harness.buffer(0.25))

        #expect(await harness.next(3) == [.starting, .level(rms: 0.5), .level(rms: 0.25)])
    }

    // MARK: - Engine selection (F23)

    @Test func engineSelectedAtPressAndListenerAttachedAfterStart() async throws {
        let harness = try await Harness()
        let engine = Self.openAIEngine()
        harness.engines.set(engine: engine)

        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        harness.audio.feed(harness.buffer(0.5))

        #expect(harness.engines.callCount == 1)
        #expect(engine.sink != nil)
        #expect(harness.audio.calls.last == .attachListener(true))
        #expect(engine.fedBuffers == 1)
    }

    @Test func engineNoticeEmittedAsCaptionNotice() async throws {
        let harness = try await Harness()
        harness.engines.set(engine: nil, notice: .cloudKeyMissing(.openai))

        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        #expect(await harness.next(2) == [
            .starting,
            .captionNotice("Live transcript: OpenAI key missing — using on-device"),
        ])
    }

    @Test func speechPointerEmittedAsError() async throws {
        let harness = try await Harness()
        harness.engines.set(engine: nil, notice: .speechPermissionPointer)

        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        await harness.controller.abort()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        #expect(await harness.next(3) == [
            .starting,
            .error(EngineNotice.speechPermissionPointer.message),
            .starting,
        ])
    }

    // MARK: - Hold vs toggle (F10, F16)

    @Test func releaseUnder300msArmsToggle() async throws {
        let harness = try await Harness()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        harness.clock.advance(by: 0.05)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        #expect(!harness.audio.calls.contains(.endCapture))
        #expect(harness.paster.calls.isEmpty)
    }

    @Test func secondPressWhileToggleArmedStops() async throws {
        let harness = try await Harness()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        harness.clock.advance(by: 0.05)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        #expect(harness.paster.pasted == ["Hello world."])
    }

    @Test func releaseOver300msStopsAndProcesses() async throws {
        let harness = try await Harness()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        #expect(harness.audio.calls.contains(.endCapture))
        #expect(harness.paster.pasted == ["Hello world."])
    }

    @Test func toggleCapStopsWithOffSoundAtToggleMaxSeconds() async throws {
        let harness = try await Harness { $0.toggleMaxSeconds = 60 }
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        harness.clock.advance(by: 0.05)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        await harness.clock.waitUntilSleeping(count: 2)
        harness.clock.advance(by: 60)
        await harness.waitFor(.processing)
        await harness.controller.settle()

        #expect(harness.sounds.played.contains(.off))
        #expect(harness.paster.pasted == ["Hello world."])
    }

    @Test func pressWhileRecordingWithoutToggleIgnored() async throws {
        let harness = try await Harness()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        #expect(harness.audio.calls.filter { $0 == .beginCapture }.count == 1)
        #expect(harness.engines.callCount == 1)
    }

    // MARK: - Mic failure and the recording gate (F11, F16)

    @Test func micStartFailureEmitsMicErrorAndSchedulesNoIdleStop() async throws {
        let harness = try await Harness()
        harness.audio.beginFailure = StubFailure(errorDescription: "no input device")

        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        #expect(await harness.next(2) == [.starting, .error("Mic error: no input device")])
        #expect(harness.idleStops.isEmpty)
    }

    @Test func gateShortRecordingDiscardsBillsSecondsOffHides() async throws {
        let harness = try await Harness()
        harness.audio.recording = Recording(wav: Data("wav".utf8), duration: 0.1, meanRMS: 0.02)
        let engine = Self.openAIEngine()
        harness.engines.set(engine: engine)

        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        #expect(engine.finishTimeout == .seconds(0.5))
        #expect(harness.transcriber.calls.isEmpty)
        #expect(harness.paster.calls.isEmpty)
        #expect(harness.usage.added == [Self.threeOpenAISeconds])
        #expect(harness.sounds.played.contains(.off))
        await harness.waitFor(.idle)
    }

    @Test func gateQuietRecordingDiscards() async throws {
        let harness = try await Harness()
        harness.audio.recording = Recording(wav: Data("wav".utf8), duration: 2, meanRMS: 0.001)

        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        #expect(harness.transcriber.calls.isEmpty)
        #expect(harness.paster.calls.isEmpty)
        await harness.waitFor(.idle)
    }

    // MARK: - Release (F17, F15)

    @Test func releaseCapturesFrontmostAppAndResolvesProfile() async throws {
        let harness = try await Harness {
            $0.profiles = [Profile(
                id: "1",
                name: "Slack",
                bundleIDs: ["com.tinyspeck.slackmacgap"],
                cleanupEnabled: false,
                submitKey: .cmdEnter,
                cleanupPrompt: nil
            )]
        }
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.pasteSubmit)
        await harness.controller.settle()

        #expect(harness.paster.calls.map(\.pid) == [4242])
        #expect(harness.paster.calls.map(\.submit) == [.cmdEnter])
        #expect(harness.paster.pasted == ["hello world"])
        #expect(harness.history.appended.map(\.appName) == ["Slack"])
    }

    @Test func releaseEmitsProcessingAndDimmedCaption() async throws {
        let harness = try await Harness()
        let engine = Self.openAIEngine()
        harness.engines.set(engine: engine)
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        engine.sink?.onPartial("hello world")

        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.waitFor(.processing)

        #expect(await harness.next() == .caption(text: "hello world", partial: false, dimmed: true))
        await harness.controller.settle()
    }

    @Test func generationIncrementsPerRelease() async throws {
        let harness = try await Harness()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        let afterPress = harness.controller.generation

        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        #expect(harness.controller.generation == afterPress + 1)
    }

    @Test func newPressDuringProcessingMakesJobStale() async throws {
        let cleaner = HookCleaner()
        let harness = try await Harness(cleaner: cleaner)
        let engine = Self.openAIEngine()
        harness.engines.set(engine: engine)
        cleaner.hook = { @Sendable [controller = harness.controller] in
            await MainActor.run { controller.hotkeyPressed(.paste) }
        }

        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        #expect(harness.paster.calls.isEmpty)
        #expect(harness.history.appended.isEmpty)
        #expect(harness.usage.added == [Self.threeOpenAISeconds])
    }

    // MARK: - Corrections (R12, R13, R15)

    /// R12: the delivery app is fixed by the press, so a switch before the press task
    /// even runs cannot change which rules were sent as hints.
    @Test func frontmostAppIsCapturedAtPressAndDrivesTheEngineHints() async throws {
        let harness = try await Harness {
            $0.corrections = [
                CorrectionRule(
                    heard: "get hub", write: "GitHub", bundleID: Self.slack.bundleID
                ),
                CorrectionRule(
                    heard: "eefa", write: "Aoife", bundleID: Self.terminal.bundleID
                ),
            ]
        }

        harness.controller.hotkeyPressed(.paste)
        harness.frontmost.target = Self.terminal
        #expect(await harness.next() == .starting)
        await harness.controller.settle()

        #expect(harness.engines.requestedHints.map(\.terms) == [["GitHub", "get hub"]])
    }

    @Test func pressSnapshotSurvivesAConfigEditBeforeRelease() async throws {
        let harness = try await Harness {
            $0.cleanupEnabled = false
            $0.corrections = [CorrectionRule(heard: "hello", write: "Hi")]
        }
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        try await harness.store.update { @Sendable in
            $0.corrections = [CorrectionRule(heard: "world", write: "Earth")]
        }
        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        #expect(harness.paster.pasted == ["Hi world"])
    }

    /// R13: hints follow the press app, the applied rules follow the release app.
    @Test func releaseUsesTheReleaseAppWithThePressSnapshot() async throws {
        let harness = try await Harness {
            $0.cleanupEnabled = false
            $0.corrections = [
                CorrectionRule(heard: "hello", write: "Hi", bundleID: Self.terminal.bundleID),
                CorrectionRule(heard: "world", write: "Earth", bundleID: Self.slack.bundleID),
            ]
        }
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        harness.frontmost.target = Self.terminal

        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        #expect(harness.engines.requestedHints.map(\.terms) == [["Earth", "world"]])
        #expect(harness.paster.calls.map(\.pid) == [Self.terminal.pid])
        #expect(harness.paster.pasted == ["Hi world"])
        #expect(harness.history.appended.map(\.appName) == ["Terminal"])
    }

    @Test func releaseBeforeStartStreamFallsBackToTheReleaseConfig() async throws {
        let harness = try await Harness { $0.cleanupEnabled = false }
        harness.audio.blockCancelIdleStop()

        harness.controller.hotkeyPressed(.paste)
        try await harness.store.update { @Sendable in
            $0.corrections = [CorrectionRule(heard: "hello", write: "Hi")]
        }
        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.waitFor(.processing)
        harness.audio.releaseCancelIdleStop()
        await harness.controller.settle()

        #expect(harness.engines.callCount == 0)
        #expect(harness.paster.pasted == ["Hi world"])
    }

    /// R15: the caption shows what the recognizer heard; only the delivered text is corrected.
    @Test func rulesNeverChangeTheLiveCaption() async throws {
        let harness = try await Harness {
            $0.cleanupEnabled = false
            $0.corrections = [CorrectionRule(heard: "get hub", write: "GitHub")]
        }
        let engine = FakeStreamingEngine(
            name: .openai,
            result: StreamResult(
                text: "get hub actions", ok: true, usage: StreamUsage(seconds: 3)
            )
        )
        harness.engines.set(engine: engine)
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()
        engine.sink?.onPartial("get hub actions")

        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        let captions = await harness.next(6).compactMap { event -> String? in
            if case .caption(let text, _, _) = event { text } else { nil }
        }
        #expect(captions == ["get hub actions", "get hub actions"])
        #expect(harness.paster.pasted == ["GitHub actions"])
    }

    // MARK: - Idle stop (F18)

    @Test func idleStopScheduledFromProcessingTerminus() async throws {
        let harness = try await Harness()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        #expect(harness.idleStops.count == 2)
    }

    @Test func idleStopUsesConfiguredSeconds() async throws {
        let harness = try await Harness { $0.idleStopSeconds = 30 }
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        #expect(harness.idleStops.allSatisfy { $0 == .seconds(30) })
    }

    // MARK: - Device changes (F19)

    @Test func deviceChangedDuringCaptureEndsWithErrorAndBillsSeconds() async throws {
        let harness = try await Harness()
        let engine = Self.openAIEngine()
        harness.engines.set(engine: engine)
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        harness.audio.send(.deviceChanged)
        await harness.waitFor(.error("Audio device changed"))

        #expect(engine.finishTimeout == .seconds(0.5))
        #expect(harness.usage.added == [Self.threeOpenAISeconds])
        #expect(harness.audio.calls.contains(.endCapture))
    }

    @Test func deviceChangedWhileIdleIsIgnoredByController() async throws {
        let harness = try await Harness()

        harness.audio.send(.deviceChanged)
        await harness.drainTimers()
        harness.controller.hotkeyPressed(.paste)

        #expect(await harness.next() == .starting)
        #expect(harness.sounds.played.isEmpty)
        await harness.controller.settle()
    }

    // MARK: - Abort and timers

    @Test func abortFinishesEngineWith500msBillsAndStopsAudio() async throws {
        let harness = try await Harness()
        let engine = Self.openAIEngine()
        harness.engines.set(engine: engine)
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        await harness.controller.abort()

        #expect(engine.finishTimeout == .seconds(0.5))
        #expect(harness.usage.added == [Self.threeOpenAISeconds])
        #expect(harness.audio.calls.contains(.stop))
        #expect(harness.paster.calls.isEmpty)
    }

    @Test func noPollingTimers() async throws {
        let harness = try await Harness()
        harness.controller.hotkeyPressed(.paste)
        await harness.controller.settle()

        harness.clock.advance(by: 0.5)
        harness.controller.hotkeyReleased(.paste)
        await harness.controller.settle()

        #expect(harness.clock.sleeps == [0.1])
    }
}
