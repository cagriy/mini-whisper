import Foundation
import Testing

import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWSupport
import MWTestSupport

/// The silence prompt in the controller (design v7 §5.1, §5.5, §5.6): the watch fed from the
/// session, the ticker, Pause, Resume and Stop, and the stop after the countdown expires.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MeetingControllerSilenceTests {
    private static let opened = MeetingEvent.silence(.open(minutes: 1, secondsLeft: 60))
    private static let closed = MeetingEvent.silence(.closed)

    // MARK: - Opening

    @Test func promptOpensAtThreeMinutesWithoutSpeech() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 179)
        events += await harness.settle(at: 180)
        events += await harness.finish()

        #expect(Self.prompts(events) == [.open(minutes: 1, secondsLeft: 60), .closed])
        #expect(try #require(events.firstIndex(of: Self.opened)) > #require(events.firstIndex(of: .elapsed(180))))
    }

    @Test func emptyPartialsDoNotDelayThePrompt() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 150)
        try harness.sink(1).onPartial("")
        events += await harness.waitFor(.partial("", speaker: nil))
        events += await harness.settle(at: 180)
        events += await harness.finish()

        #expect(Self.prompts(events) == [.open(minutes: 1, secondsLeft: 60), .closed])
        #expect(try #require(events.firstIndex(of: Self.opened)) > #require(events.firstIndex(of: .elapsed(180))))
    }

    @Test func aSegmentDelaysThePrompt() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 170)
        try await harness.deliverSegment()
        for second in [180.0, 229, 230] { events += await harness.settle(at: second) }
        events += await harness.finish()

        #expect(Self.prompts(events) == [.open(minutes: 1, secondsLeft: 60), .closed])
        #expect(try #require(events.firstIndex(of: Self.opened)) > #require(events.firstIndex(of: .elapsed(230))))
    }

    @Test func aFirstConnectedDoesNotRestartTheClock() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 100)
        try harness.sink(1).onPartial("")
        events += await harness.waitFor(.partial("", speaker: nil))
        events += await harness.settle(at: 180)
        events += await harness.finish()

        #expect(events.contains(.connection(.connected)))
        #expect(Self.prompts(events) == [.open(minutes: 1, secondsLeft: 60), .closed])
        #expect(try #require(events.firstIndex(of: Self.opened)) > #require(events.firstIndex(of: .elapsed(180))))
    }

    @Test func twoMinuteSettingOpensWithItsMinutes() async throws {
        let harness = try await MeetingHarness { $0.meetingSilenceStopSeconds = 120 }
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 180)
        events += await harness.finish()

        #expect(Self.prompts(events) == [.open(minutes: 2, secondsLeft: 60), .closed])
    }

    // MARK: - Closing

    @Test func aNewPartialClosesTheOpenPrompt() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 180)
        try harness.sink(1).onPartial("we're back")
        events += await harness.waitFor(.partial("we're back", speaker: nil))
        // An open prompt would count down on this tick.
        events += await harness.settle(at: 181)
        events += await harness.finish()

        #expect(Self.prompts(events) == [.open(minutes: 1, secondsLeft: 60), .closed])
        #expect(try #require(events.firstIndex(of: Self.closed)) < #require(events.firstIndex(of: .elapsed(181))))
    }

    @Test func pauseClosesAndResumeCountsFromResume() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 180)
        await harness.controller.pause()
        events += await harness.settle(at: 200)
        events += await harness.settle(at: 210)
        await harness.controller.resume()
        events += await harness.settle(at: 269)
        events += await harness.settle(at: 270)
        events += await harness.finish()

        #expect(Self.prompts(events) == [
            .open(minutes: 1, secondsLeft: 60), .closed, .open(minutes: 1, secondsLeft: 60), .closed,
        ])
        #expect(try #require(events.firstIndex(of: Self.closed)) < #require(events.firstIndex(of: .state(.paused(.user)))))
        #expect(try #require(events.lastIndex(of: Self.opened)) > #require(events.firstIndex(of: .elapsed(270))))
    }

    @Test func sleepClosesThePrompt() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 180)
        harness.audio.sendMeeting(.systemWillSleep)
        events += await harness.waitFor(.state(.paused(.sleep)))
        events += await harness.finish()

        #expect(Self.prompts(events) == [.open(minutes: 1, secondsLeft: 60), .closed])
        #expect(try #require(events.firstIndex(of: Self.closed)) < #require(events.firstIndex(of: .state(.paused(.sleep)))))
    }

    @Test func reconnectingClosesAndConnectedCountsFromThere() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 180)
        try harness.sink(1).onEngineError(WebSocketConnectionError.closed(code: 4005, reason: nil))
        events += await harness.waitFor(.connection(.reconnecting(attempt: 1)))
        // The ticker and the 1 s reopen timer.
        await harness.clock.waitUntilSleeping(count: 2)
        events += await harness.settle(at: 200)
        await harness.engines.waitUntilStarted(2)
        try harness.sink(2).onPartial("")
        events += await harness.waitFor(.partial("", speaker: nil))
        events += await harness.settle(at: 259)
        events += await harness.settle(at: 260)
        events += await harness.finish()

        #expect(Self.prompts(events) == [
            .open(minutes: 1, secondsLeft: 60), .closed, .open(minutes: 1, secondsLeft: 60), .closed,
        ])
        let reconnecting = try #require(events.firstIndex(of: .connection(.reconnecting(attempt: 1))))
        #expect(events[reconnecting + 1] == Self.closed)
        #expect(try #require(events.lastIndex(of: Self.opened)) > #require(events.firstIndex(of: .elapsed(260))))
    }

    @Test func keepRecordingClosesAndCountsFromTheClick() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 180)
        events += await harness.settle(at: 190)
        harness.controller.keepRecording()
        events += await harness.settle(at: 249)
        events += await harness.settle(at: 250)
        events += await harness.finish()

        #expect(Self.prompts(events) == [
            .open(minutes: 1, secondsLeft: 60), .open(minutes: 1, secondsLeft: 50), .closed,
            .open(minutes: 1, secondsLeft: 60), .closed,
        ])
        #expect(try #require(events.lastIndex(of: Self.opened)) > #require(events.firstIndex(of: .elapsed(250))))
    }

    @Test func offDuringTheCountdownClosesOnTheNextTick() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 180)
        events += await harness.settle(at: 190)
        try await harness.config.update { @Sendable config in config.meetingSilenceStopSeconds = 0 }
        events += await harness.settle(at: 191)
        events += await harness.settle(at: 192)
        events += await harness.finish()

        #expect(Self.prompts(events) == [
            .open(minutes: 1, secondsLeft: 60), .open(minutes: 1, secondsLeft: 50), .closed,
        ])
        #expect(try #require(events.firstIndex(of: Self.closed)) > #require(events.firstIndex(of: .elapsed(191))))
        #expect(try #require(events.firstIndex(of: Self.closed)) < #require(events.firstIndex(of: .elapsed(192))))
    }

    @Test func anyStopWhileOpenEmitsClosed() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 180)
        events += await harness.finish()

        #expect(Self.prompts(events) == [.open(minutes: 1, secondsLeft: 60), .closed])
        #expect(try #require(events.firstIndex(of: Self.closed)) < #require(events.firstIndex(of: .state(.stopping))))
        #expect(try harness.stored().meeting.silenceStopSeconds == nil)
    }

    // MARK: - Never

    @Test func aTestCallNeverPrompts() async throws {
        let harness = try await MeetingHarness()
        try await harness.controller.start(
            mode: .remote, title: "Test call · Sprint planning", engine: nil,
            test: TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")
        )

        var events: [MeetingEvent] = []
        for second in [180.0, 240, 300] { events += await harness.settle(at: second) }
        events += await harness.finish()

        #expect(Self.prompts(events).isEmpty)
    }

    @Test func offNeverPrompts() async throws {
        let harness = try await MeetingHarness { $0.meetingSilenceStopSeconds = 0 }
        try await harness.start(.inRoom)

        var events: [MeetingEvent] = []
        for second in [180.0, 240, 600] { events += await harness.settle(at: second) }
        events += await harness.finish()

        #expect(Self.prompts(events).isEmpty)
    }

    // MARK: - Stop after silence

    @Test func stopAfterSilenceBeforeExpiryDoesNothing() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 180)
        events += await harness.settle(at: 200)
        await harness.controller.stopAfterSilence()

        #expect(harness.controller.state == .recording)
        #expect(harness.controller.meeting?.silenceStopSeconds == nil)
        events += await harness.finish()
        #expect(Self.prompts(events) == [
            .open(minutes: 1, secondsLeft: 60), .open(minutes: 1, secondsLeft: 40), .closed,
        ])
        #expect(try harness.stored().meeting.silenceStopSeconds == nil)
    }

    @Test func stopAfterSilenceAfterExpiryStopsSummarisesAndRecordsTheThreshold() async throws {
        let harness = try await MeetingHarness(secrets: [.speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key])
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 10)
        try await harness.deliverSegment()
        events += await harness.settle(at: 180)
        events += await harness.settle(at: 240)
        await harness.controller.stopAfterSilence()
        // It returns once stopped and summarised, so the wait below cannot hang.
        try #require(harness.controller.state == .stopped)
        events += await harness.waitFor { if case .summary(.ready) = $0 { true } else { false } }

        #expect(Self.prompts(events) == [.open(minutes: 1, secondsLeft: 60), .expired])
        #expect(try #require(events.firstIndex(of: .silence(.expired))) < #require(events.firstIndex(of: .state(.stopping))))
        #expect(try harness.stored().meeting.silenceStopSeconds == 60)
        #expect(try harness.stored().meeting.summary != nil)
    }

    @Test func theExpiredPromptsThresholdIsRecorded() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        var events = await harness.settle(at: 180)
        try await harness.config.update { @Sendable config in config.meetingSilenceStopSeconds = 300 }
        events += await harness.settle(at: 200)
        events += await harness.settle(at: 240)
        await harness.controller.stopAfterSilence()
        try #require(harness.controller.state == .stopped)
        events += await harness.waitFor(.state(.stopped))

        #expect(Self.prompts(events) == [
            .open(minutes: 1, secondsLeft: 60), .open(minutes: 1, secondsLeft: 40), .expired,
        ])
        #expect(try harness.stored().meeting.silenceStopSeconds == 60)
    }

    // MARK: - Logs

    /// Design v7 §5.7: times and reasons, never transcript text.
    @Test func logsCarryTimesNotTranscriptText() async throws {
        let sink = CapturingLogSink()
        let harness = try await MeetingHarness()

        try await logging(to: sink) {
            try await harness.start(.inRoom)
            _ = await harness.settle(at: 10)
            try harness.sink(1).onPartial("the merger")
            await harness.waitFor(.partial("the merger", speaker: nil))
            _ = await harness.settle(at: 180)
            try harness.sink(1).onPartial("the merger price")
            await harness.waitFor(.partial("the merger price", speaker: nil))
            _ = await harness.finish()
        }

        #expect(sink.lines.contains("INFO meeting silence prompt shown after 170 s"))
        #expect(sink.lines.contains("INFO meeting silence prompt closed (speech)"))
        for line in sink.lines {
            #expect(!line.contains("merger"), "\(line)")
        }
    }

    /// The prompt changes in `events`, in order.
    private static func prompts(_ events: [MeetingEvent]) -> [SilencePrompt] {
        events.compactMap { if case .silence(let prompt) = $0 { prompt } else { nil } }
    }
}

private extension MeetingHarness {
    /// Ticks to `second` and lets that tick's silence check finish, so what the test does
    /// next lands after it.
    func settle(at second: Double) async -> [MeetingEvent] {
        let events = await tick(to: second)
        await clock.waitUntilSleeping()
        return events
    }

    /// Stops without a summary; the events up to `.state(.stopped)`.
    func finish() async -> [MeetingEvent] {
        await controller.stop(summarise: false)
        return await waitFor(.state(.stopped))
    }
}
