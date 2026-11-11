import AVFAudio
import Foundation
import Testing

import MWAudio
import MWConfig
import MWCorrections
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWSupport
import MWTestSupport
import MWTranscription
import MWUsage

/// Start, the audio tick, segments, Stop, persistence, billing and the summary (design §5.6).
@MainActor
@Suite struct MeetingControllerTests {
    // MARK: - Start

    @Test func startWithoutAnyKeyThrowsNoEngineKey() async throws {
        let harness = try await MeetingHarness(secrets: [:]) { $0.meetingEngine = .assemblyaiPro }

        await #expect(throws: MeetingError.noEngineKey) { try await harness.start() }

        #expect(harness.controller.state == .idle)
        #expect(harness.audio.calls.isEmpty)
        #expect(harness.engines.calls.isEmpty)
        #expect(try harness.store.index().isEmpty)
    }

    @Test func startUsesTheConfiguredTierAndItsKey() async throws {
        let speechmatics = "placeholder-not-a-real-key-speechmatics"
        let assemblyAI = "placeholder-not-a-real-key-assemblyai"
        let harness = try await MeetingHarness(secrets: [.speechmatics: speechmatics, .assemblyai: assemblyAI]) {
            $0.meetingEngine = .assemblyaiPro
            $0.vocabulary = ["Northwind"]
        }

        try await harness.start()

        let hints = HintResolver.resolve(CorrectionSnapshot(config: await harness.config.load()), bundleID: nil)
        #expect(hints.vocabulary == ["Northwind"])
        #expect(harness.engines.calls.map(\.engine) == [.assemblyaiPro])
        #expect(harness.engines.calls.map(\.key) == [assemblyAI])
        #expect(harness.engines.calls.map(\.hints) == [hints])
    }

    @Test func startHoldsCaptureEnablesVoiceProcessingAndAttachesTheMeetingListener() async throws {
        let harness = try await MeetingHarness()

        try await harness.start()

        #expect(harness.audio.calls == [
            .holdRunning(true), .setVoiceProcessing(true), .ensureRunning, .attachMeetingListener(true),
        ])
        #expect(harness.audio.meetingListener != nil)
        await harness.waitFor(.state(.recording))
        #expect(harness.controller.state == .recording)
    }

    @Test func remoteStartStartsTheTapExcludingOurPID() async throws {
        let harness = try await MeetingHarness()

        try await harness.start(.remote)

        #expect(harness.tapFactory.excludedPIDs == [ProcessInfo.processInfo.processIdentifier])
        #expect(harness.tap?.startCount == 1)
        let events = await harness.waitFor(.state(.recording))
        #expect(events.contains(.systemAudio(.on)))
    }

    @Test func tapStartFailureContinuesMicOnly() async throws {
        let harness = try await MeetingHarness()
        harness.tap?.startError = StubError(errorDescription: "no output device")

        try await harness.start(.remote)

        let events = await harness.waitFor(.state(.recording))
        #expect(events.contains(.systemAudio(.unavailable("no output device"))))
        harness.feed(MeetingHarness.loud(0.2))
        #expect(harness.engines.engines.first?.fedBuffers == 2)
    }

    @Test func remoteWithoutATapFactoryResultRunsMicOnly() async throws {
        let harness = try await MeetingHarness(tap: nil)

        try await harness.start(.remote)

        let events = await harness.waitFor(.state(.recording))
        #expect(events.contains(.systemAudio(.unavailable("needs macOS 14.2"))))
        harness.feed(MeetingHarness.loud(0.2))
        #expect(harness.engines.engines.first?.fedBuffers == 2)
    }

    @Test func startCreatesTheMeetingOnDiskWithTitleAppModeAndEngine() async throws {
        let harness = try await MeetingHarness()

        try await harness.start(.inRoom)

        let meeting = try harness.stored().meeting
        #expect(meeting == harness.controller.meeting)
        #expect(meeting.title == MeetingHarness.title)
        #expect(meeting.app == "Zoom")
        #expect(meeting.mode == .inRoom)
        #expect(meeting.engine == .speechmaticsStandard)
        #expect(meeting.startedAt == MeetingHarness.wallStart)
        #expect(meeting.endedAt == nil)
        #expect(meeting.userName == "Alex")
        #expect(meeting.speakers == [SpeakerLabel(id: 0, name: "Alex", isUser: true)])
    }

    @Test func firstRemoteStartSetsSystemAudioExplained() async throws {
        let remote = try await MeetingHarness()
        let inRoom = try await MeetingHarness()

        try await remote.start(.remote)
        try await inRoom.start(.inRoom)

        #expect(await remote.config.load().meetingSystemAudioExplained)
        #expect(await !inRoom.config.load().meetingSystemAudioExplained)
    }

    // MARK: - Audio tick

    @Test func remoteTickFeedsMixedAudioToTheSessionTheRecorderAndBilling() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        let system = SignalFixtures.ramp(count: 1600, from: -0.2, to: 0.2)
        let mic = SignalFixtures.sine(count: 4800, sampleRate: 48_000, amplitude: 0.3, noise: 0)

        harness.pushSystem(system)
        harness.feed(mic, rate: 48_000)

        var resampler = PCMConverter(from: 48_000, to: 16_000)
        var recorderConverter = PCMConverter(from: 16_000, to: 16_000)
        let mixed = AudioMixer.mix(mic: resampler.resample(mic), system: system)
        #expect(mixed.count == 1600)
        #expect(harness.writers.last?.events == [.write(recorderConverter.convert(mixed))])
        #expect(harness.engines.engines.first?.fedBuffers == 1)

        await harness.controller.stop()
        #expect(try harness.stored().meeting.billing.engineSeconds == 1600.0 / 16_000)
    }

    /// Voice processing ducks other apps' audio, and the tap hears the call ducked.
    @Test func remoteTickRaisesAQuietCallBeforeMixing() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        let amplitude = Float(pow(10, -46.0 / 20) * 2.0.squareRoot())
        let call = SignalFixtures.sine(count: 6 * 16_000, sampleRate: 16_000, amplitude: amplitude, noise: 0)

        for start in stride(from: 0, to: call.count, by: 1600) {
            harness.pushSystem(Array(call[start..<start + 1600]))
            harness.feed(MeetingHarness.quiet(0.1))
        }

        let written = (harness.writers.last?.events ?? []).flatMap { event -> [Float] in
            guard case .write(let pcm) = event else { return [] }
            return pcm.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map { Float(Int16(littleEndian: $0)) / 32767 }
        }
        let lastSecond = written.suffix(16_000)
        let level = 10 * log10(lastSecond.reduce(0) { $0 + Double($1) * Double($1) } / Double(lastSecond.count))
        #expect(abs(Float(level) - SystemAudioLeveller.targetDBFS) < 1.5)
    }

    @Test func inRoomTickBypassesTheGateAndTheMixer() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        let chunks = [MeetingHarness.loud(0.1), MeetingHarness.loud(0.1)]

        chunks.forEach { harness.feed($0) }
        try harness.sink(1).onPartial("so the")

        #expect(harness.tapFactory.excludedPIDs.isEmpty)
        var converter = PCMConverter(from: 16_000, to: 16_000)
        #expect(harness.writers.last?.events == chunks.map { .write(converter.convert($0)) })
        #expect(harness.engines.engines.first?.fedBuffers == 2)
        #expect(await harness.nextPartial() == .partial("so the", speaker: nil))
    }

    // MARK: - Segments and partials

    @Test func segmentIsShiftedAttributedPersistedAndEmitted() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        harness.feed(MeetingHarness.loud(1) + MeetingHarness.quiet(1))
        // A Speechmatics session-limit warning rolls over at once, so session 2 starts at 2 s.
        try harness.sink(1).onSessionLimit(.warning)
        harness.feed(MeetingHarness.loud(1) + MeetingHarness.quiet(1))

        try harness.sink(2).onSegment(TranscriptSegment(
            text: "hello there",
            words: [TranscriptWord(text: "hello", start: 0.2, end: 0.5), TranscriptWord(text: "there", start: 1.3, end: 1.6)],
            speaker: "S1",
            start: 0.2,
            end: 1.6
        ))

        let events = await harness.waitFor { if case .segmentAdded(let s) = $0 { s.speaker == 1 } else { false } }
        let added = events.compactMap { if case .segmentAdded(let s) = $0 { s } else { nil } }
        let expected = [
            Segment(speaker: 0, start: 2.0 + 0.2, end: 2.0 + 0.5, text: "hello",
                    words: [Word(text: "hello", start: 2.0 + 0.2, end: 2.0 + 0.5)], session: 2, providerLabel: "S1"),
            Segment(speaker: 1, start: 2.0 + 1.3, end: 2.0 + 1.6, text: "there",
                    words: [Word(text: "there", start: 2.0 + 1.3, end: 2.0 + 1.6)], session: 2, providerLabel: "S1"),
        ]
        #expect(MeetingHarness.unidentified(added) == MeetingHarness.unidentified(expected))
        #expect(events.contains(.speakers([
            SpeakerLabel(id: 0, name: "Alex", isUser: true),
            SpeakerLabel(id: 1, name: "Speaker 1", providerKeys: ["2:S1"]),
        ])))
        #expect(try harness.stored().segments == added)
    }

    @Test func partialIsTaggedWithTheUserWhileTheGateIsOpen() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)

        harness.feed(MeetingHarness.loud(0.2))
        try harness.sink(1).onPartial("so the")
        #expect(await harness.nextPartial() == .partial("so the", speaker: 0))

        harness.feed(MeetingHarness.quiet(0.5))
        try harness.sink(1).onPartial("so the plan")
        #expect(await harness.nextPartial() == .partial("so the plan", speaker: nil))
    }

    @Test func elapsedAndCostTickEverySecond() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        harness.feed(MeetingHarness.quiet(1))
        var billing = MeetingBilling(engine: .speechmaticsStandard, overrides: [:])
        for _ in 0..<10 { billing.add(seconds: 0.1) }

        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 1)
        await harness.waitFor(.elapsed(1))
        #expect(await harness.next() == .cost(billing.liveCost))

        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 1)
        await harness.waitFor(.elapsed(2))
        #expect(await harness.next() == .cost(billing.liveCost))
    }

    // MARK: - Stop

    @Test func stopDrainsTheSessionReleasesCaptureAndStopsTheTap() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        let calls = harness.audio.calls.count

        try harness.sink(1).onSegment(TranscriptSegment(text: "last words", start: 0, end: 1))
        await harness.controller.stop()

        #expect(harness.engines.engines.first?.finishTimeout == .seconds(5))
        #expect(Array(harness.audio.calls.dropFirst(calls)) == [
            .attachMeetingListener(false), .holdRunning(false), .setVoiceProcessing(false),
            .scheduleIdleStop(.seconds(60)),
        ])
        #expect(harness.audio.meetingListener == nil)
        #expect(harness.tap?.stopCount == 1)
        #expect(harness.writers.last?.events.last == .finish)
        #expect(harness.controller.state == .stopped)
        // The segment delivered just before Stop is drained, not dropped.
        let events = await harness.waitFor(.state(.stopped))
        #expect(events.contains { if case .segmentAdded = $0 { true } else { false } })
        #expect(try harness.stored().segments.map(\.text) == ["last words"])
    }

    @Test func stopWritesEndedAtDurationAndBilling() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        harness.feed(MeetingHarness.quiet(2))
        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 5)

        await harness.controller.stop()

        var billing = MeetingBilling(engine: .speechmaticsStandard, overrides: [:])
        for _ in 0..<20 { billing.add(seconds: 0.1) }
        let meeting = try harness.stored().meeting
        #expect(meeting.endedAt == MeetingHarness.wallStart.addingTimeInterval(5))
        #expect(meeting.durationSeconds == 5)
        #expect(meeting.billing == billing.totals)
        #expect(meeting == harness.controller.meeting)
    }

    @Test func stopAddsOneUsageRecord() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        harness.feed(MeetingHarness.quiet(2))

        await harness.controller.stop()

        var billing = MeetingBilling(engine: .speechmaticsStandard, overrides: [:])
        for _ in 0..<20 { billing.add(seconds: 0.1) }
        #expect(harness.usage.added == [billing.finalUsage()])
        #expect(billing.finalUsage().streamedSeconds.keys.sorted() == ["speechmatics"])
    }

    @Test func stopWithoutAnAnthropicKeyReportsNoSummary() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        try await harness.deliverSegment()

        await harness.controller.stop()

        let events = await harness.waitFor { if case .summary = $0 { true } else { false } }
        #expect(events.last == .summary(.none("No summary: add an Anthropic key under Keys.")))
        #expect(harness.summarizer.calls.isEmpty)
    }

    @Test func stopWithAKeyStoresTheSummaryAndBillsItsTokens() async throws {
        let tokens = TokenUsage(inputTokens: 1200, outputTokens: 300)
        let harness = try await MeetingHarness(
            secrets: [.speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key],
            summarizer: FakeSummarizer(result: SummaryResult(text: "## Summary\n\nShipped.", usage: tokens))
        )
        try await harness.start(.remote)
        harness.feed(MeetingHarness.quiet(1))
        try await harness.deliverSegment()

        await harness.controller.stop()

        let summary = Summary(
            text: "## Summary\n\nShipped.",
            model: AnthropicClient.model,
            createdAt: MeetingHarness.wallStart,
            inputTokens: 1200,
            outputTokens: 300,
            costUSD: Pricing.meetingCost(engine: .speechmaticsStandard, seconds: 0, tokens: tokens, overrides: [:])
        )
        let events = await harness.waitFor(.summary(.ready(summary)))
        #expect(events.contains(.summary(.writing)))
        #expect(harness.summarizer.calls.count == 1)
        #expect(try harness.stored().meeting.summary == summary)
        #expect(harness.controller.meeting?.summary == summary)
        #expect(harness.usage.added.count == 2)
        #expect(harness.usage.added.last == ProviderUsage(inputTokens: 1200, outputTokens: 300, costUSD: summary.costUSD))
    }

    @Test func summaryFailureLeavesNoSummary() async throws {
        let harness = try await MeetingHarness(
            secrets: [.speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key],
            summarizer: FakeSummarizer(failure: APIError.httpStatus(503))
        )
        try await harness.start(.remote)
        harness.feed(MeetingHarness.quiet(1))
        try await harness.deliverSegment()

        await harness.controller.stop()

        let events = await harness.waitFor { if case .summary(.failed) = $0 { true } else { false } }
        #expect(events.last == .summary(.failed("API error (503).")))
        #expect(try harness.stored().meeting.summary == nil)
        #expect(harness.usage.added.count == 1)
    }

    @Test func refusalReadsSummaryDeclinedWithCategory() async throws {
        let harness = try await MeetingHarness(
            secrets: [.speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key],
            summarizer: FakeSummarizer(result: SummaryResult(text: "", refusalCategory: "cyber"))
        )
        try await harness.start(.remote)
        try await harness.deliverSegment()

        await harness.controller.stop()

        let events = await harness.waitFor { if case .summary(.failed) = $0 { true } else { false } }
        #expect(events.last == .summary(.failed("Summary declined (cyber)")))
        #expect(try harness.stored().meeting.summary == nil)
    }

    @Test func emptyTranscriptReportsNothingTranscribed() async throws {
        let harness = try await MeetingHarness(
            secrets: [.speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key]
        )
        try await harness.start(.remote)

        await harness.controller.stop()

        let events = await harness.waitFor { if case .summary = $0 { true } else { false } }
        #expect(events.last == .summary(.none("Nothing was transcribed.")))
        #expect(harness.summarizer.calls.isEmpty)
    }

    @Test func keepAudioOffWritesNoAudioFile() async throws {
        let kept = try await MeetingHarness()
        let dropped = try await MeetingHarness { $0.meetingKeepAudio = false }

        try await kept.start(.remote)
        try await dropped.start(.remote)
        dropped.feed(MeetingHarness.loud(0.2))
        await dropped.controller.stop()

        let keptID = try #require(kept.controller.meeting?.id)
        #expect(kept.writers.urls == [kept.store.audioURL(keptID)])
        #expect(dropped.writers.urls.isEmpty)
        let droppedID = try #require(dropped.controller.meeting?.id)
        #expect(!FileManager.default.fileExists(atPath: dropped.store.audioURL(droppedID).path))
    }
}

// MARK: - Harness (shared by every MeetingController suite)

struct StubError: LocalizedError, Equatable {
    let errorDescription: String?
}

struct StubSummaryPrompt: SummaryPromptProviding {
    func summaryPrompt() throws -> String { "Summarise the meeting." }
}

final class NoFileWatcher: FileWatcher, @unchecked Sendable {
    func start(url: URL, onChange: @escaping @Sendable () -> Void) {}
    func stop() {}
}

/// Hands out a `FakeAudioFileWriter` per meeting and records where each was asked to write.
final class AudioWriterLog: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [(url: URL, writer: FakeAudioFileWriter)] = []

    var urls: [URL] { lock.withLock { made.map(\.url) } }
    var last: FakeAudioFileWriter? { lock.withLock { made.last?.writer } }

    func make(_ url: URL) -> any AudioFileWriting {
        let writer = FakeAudioFileWriter()
        lock.withLock { made.append((url, writer)) }
        return writer
    }
}

/// Pulls the controller's events off the main actor.
final class MeetingEventPuller: @unchecked Sendable {
    private var iterator: AsyncStream<MeetingEvent>.AsyncIterator

    init(_ stream: AsyncStream<MeetingEvent>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async -> MeetingEvent? { await iterator.next() }
}

@MainActor
final class MeetingHarness {
    nonisolated static let key = "placeholder-not-a-real-key"
    nonisolated static let wallStart = Date(timeIntervalSince1970: 1_794_234_600)
    nonisolated static let title = "Zoom · 9 Nov 2026 14:30"

    let clock = VirtualClock()
    let audio = FakeAudioCapture()
    let tapFactory: FakeSystemAudioTapFactory
    let engines = FakeMeetingEngineProvider()
    let secrets: FakeSecretStore
    let summarizer: FakeSummarizer
    let usage = FakeUsageStore()
    let writers = AudioWriterLog()
    let directory: TempDirectory
    let store: MeetingStore
    let config: ConfigStore
    let controller: MeetingController
    private let puller: MeetingEventPuller

    init(
        secrets: [KeyAccount: String] = [.speechmatics: MeetingHarness.key],
        tap: FakeSystemAudioTap? = FakeSystemAudioTap(),
        summarizer: FakeSummarizer = FakeSummarizer(result: SummaryResult(text: "## Summary\n\nShipped.")),
        _ configure: @escaping @Sendable (inout Config) -> Void = { _ in }
    ) async throws {
        tapFactory = FakeSystemAudioTapFactory(tap: tap)
        self.secrets = FakeSecretStore(secrets)
        self.summarizer = summarizer
        directory = try TempDirectory()
        store = MeetingStore(directory: directory.file("meetings"))
        config = ConfigStore(directory: directory.url, watcher: NoFileWatcher())
        try await config.update(configure)
        let clock = clock
        controller = MeetingController(
            deps: MeetingDependencies(
                audio: audio,
                tapFactory: tapFactory,
                engines: engines,
                secrets: self.secrets,
                store: store,
                summarizer: summarizer,
                usage: usage,
                prompts: StubSummaryPrompt(),
                frontAppName: { "Zoom" },
                userName: { "Alex" },
                clock: clock,
                now: { MeetingHarness.wallStart.addingTimeInterval(clock.now) },
                makeAudioWriter: { [writers] in writers.make($0) }
            ),
            config: config
        )
        puller = MeetingEventPuller(controller.events)
    }

    var tap: FakeSystemAudioTap? { tapFactory.tap }

    func start(_ mode: MeetingMode = .remote) async throws {
        try await controller.start(mode: mode, title: Self.title)
    }

    /// Feeds `samples` through the capture tap in 0.1 s buffers.
    func feed(_ samples: [Float], rate: Double = 16_000) {
        let chunk = Int(rate / 10)
        for start in stride(from: 0, to: samples.count, by: chunk) {
            let slice = Array(samples[start..<min(start + chunk, samples.count)])
            audio.feed(PCMBufferFactory.make(samples: slice, sampleRate: rate))
        }
    }

    func pushSystem(_ samples: [Float]) {
        tap?.push(PCMBufferFactory.make(samples: samples, sampleRate: 16_000))
    }

    /// The sink session `index` (from 1) was started with.
    func sink(_ index: Int) throws -> any TranscriptSink {
        let made = engines.engines
        try #require(made.count >= index)
        return try #require(made[index - 1].sink)
    }

    /// Delivers one segment on session 1 and waits until the controller has added it.
    func deliverSegment(_ text: String = "We ship on Friday.") async throws {
        try sink(1).onSegment(TranscriptSegment(text: text, speaker: "S1", start: 0, end: 1))
        await waitFor { if case .segmentAdded = $0 { true } else { false } }
    }

    func stored() throws -> LoadedMeeting {
        try store.load(#require(controller.meeting?.id))
    }

    func next() async -> MeetingEvent? { await puller.next() }

    /// Pulls events up to and including the first that matches.
    @discardableResult
    func waitFor(_ match: (MeetingEvent) -> Bool) async -> [MeetingEvent] {
        var seen: [MeetingEvent] = []
        while let event = await puller.next() {
            seen.append(event)
            if match(event) { break }
        }
        return seen
    }

    @discardableResult
    func waitFor(_ event: MeetingEvent) async -> [MeetingEvent] {
        await waitFor { $0 == event }
    }

    func nextPartial() async -> MeetingEvent? {
        await waitFor { if case .partial = $0 { true } else { false } }.last
    }

    /// 16 kHz speech-level tone the microphone gate opens on.
    static func loud(_ seconds: Double) -> [Float] {
        SignalFixtures.sine(count: Int(seconds * 16_000), sampleRate: 16_000, amplitude: 0.3, noise: 0)
    }

    static func quiet(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * 16_000))
    }

    /// Segments with their random ids blanked, for comparing content.
    static func unidentified(_ segments: [Segment]) -> [Segment] {
        segments.map { segment in
            var segment = segment
            segment.id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            return segment
        }
    }
}
