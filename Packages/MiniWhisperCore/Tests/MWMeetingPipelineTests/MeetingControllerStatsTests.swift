import Foundation
import Testing

import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStats
import MWStreaming
import MWTestSupport
import MWTranscription

/// What a meeting stores and reports for the statistics record: its UTC offset, the live
/// transcript delay, the summary wait, and its stop (design v11 §5 Meeting).
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MeetingControllerStatsTests {
    private static let keys: [KeyAccount: String] = [
        .speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key,
    ]
    private static let tag = TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")

    /// Takes down, at each report, the controller's state, the summary requests made so far and
    /// whether the stored meeting has ended.
    @MainActor
    private final class StopProbe: MeetingStatsRecording {
        struct Report: Equatable {
            let id: UUID
            let state: MeetingState?
            let summaryRequests: Int
            let storedAsEnded: Bool
        }

        weak var harness: MeetingHarness?
        private(set) var reports: [Report] = []

        func meetingStopped(_ id: UUID) async {
            reports.append(Report(
                id: id,
                state: harness?.controller.state,
                summaryRequests: harness?.summarizer.calls.count ?? -1,
                storedAsEnded: (try? harness?.store.meeting(id).endedAt) != nil
            ))
        }
    }

    /// A segment ending at meeting second `end`, delivered on session 1 now.
    private func deliver(_ harness: MeetingHarness, endingAt end: Double) async throws {
        try harness.sink(1).onSegment(TranscriptSegment(text: "We ship on Friday.", speaker: "S1", start: end - 1, end: end))
        await harness.waitFor { if case .segmentAdded = $0 { true } else { false } }
    }

    private func isSummary(_ state: SummaryState) -> (MeetingEvent) -> Bool {
        { $0 == .summary(state) }
    }

    // MARK: - Start

    @Test func startStoresTheOffsetOfItsTimeZone() async throws {
        let harness = try await MeetingHarness()

        try await harness.start()

        #expect(try harness.stored().meeting.utcOffsetSeconds == 3600)
    }

    // MARK: - Transcript delay

    /// Delivered at meeting seconds 2, 5 and 9, ending at 1, 3.5 and 5: delays 1, 1.5 and 4.
    @Test func stopWritesTheTranscriptDelayOfItsSegments() async throws {
        let harness = try await MeetingHarness()
        try await harness.start()
        for (second, end) in [(2.0, 1.0), (5.0, 3.5), (9.0, 5.0)] {
            _ = await harness.tick(to: second)
            try await deliver(harness, endingAt: end)
        }

        await harness.controller.stop()

        #expect(try harness.stored().meeting.timing?.transcriptDelay == DelayStats(median: 1.5, p90: 4, count: 3))
    }

    /// The same segment, in a meeting and in a test call.
    @Test(arguments: [false, true])
    func aTestCallTakesNoSamples(isTest: Bool) async throws {
        let harness = try await MeetingHarness()
        try await harness.controller.start(mode: .remote, title: "Call", test: isTest ? Self.tag : nil)
        _ = await harness.tick(to: 2)
        try await deliver(harness, endingAt: 1)

        await harness.controller.stop()

        let stored = try harness.stored()
        #expect(stored.segments.count == 1)
        #expect(stored.meeting.timing?.transcriptDelay == (isTest ? nil : DelayStats(median: 1, p90: 1, count: 1)))
    }

    /// The second segment drains while the session closes for the pause.
    @Test func segmentsWhilePausedTakeNoSample() async throws {
        let harness = try await MeetingHarness()
        try await harness.start()
        _ = await harness.tick(to: 2)
        try await deliver(harness, endingAt: 1)
        try harness.sink(1).onSegment(TranscriptSegment(text: "Late words.", speaker: "S1", start: 1, end: 1.5))

        await harness.controller.pause()
        await harness.controller.stop()

        let stored = try harness.stored()
        #expect(stored.segments.count == 2)
        #expect(stored.meeting.timing?.transcriptDelay == DelayStats(median: 1, p90: 1, count: 1))
    }

    // MARK: - Stop reports the meeting

    @Test func stopReportsTheMeetingOnceAfterItHasStopped() async throws {
        let probe = StopProbe()
        let harness = try await MeetingHarness(secrets: Self.keys, stats: probe)
        probe.harness = harness
        try await harness.start()
        try await deliver(harness, endingAt: 1)

        await harness.controller.stop()

        let id = try #require(harness.controller.meeting?.id)
        #expect(probe.reports == [
            StopProbe.Report(id: id, state: .stopped, summaryRequests: 0, storedAsEnded: true),
        ])
        #expect(harness.summarizer.calls.count == 1)
    }

    /// The reconciler leaves it out.
    @Test func aTestCallIsReportedToo() async throws {
        let harness = try await MeetingHarness()
        try await harness.controller.start(mode: .remote, title: "Test call · Sprint planning", test: Self.tag)

        await harness.controller.stop()

        #expect(harness.stats.stopped == [try #require(harness.controller.meeting?.id)])
    }

    // MARK: - Summary wait

    /// The request is read off the clock as it starts, before the test sees `.writing`.
    @Test func theSummaryWaitIsStored() async throws {
        let harness = try await MeetingHarness(secrets: Self.keys)
        try await harness.start()
        try await deliver(harness, endingAt: 1)
        harness.summarizer.hold()

        let stopping = Task { await harness.controller.stop() }
        await harness.waitFor(isSummary(.writing))
        harness.clock.advance(by: 4)
        harness.summarizer.release()
        await stopping.value

        #expect(try harness.stored().meeting.timing?.summaryWaitSeconds == 4)
    }

    @Test func aRegeneratedSummaryReplacesTheWait() async throws {
        let harness = try await MeetingHarness(secrets: Self.keys)
        var loaded = MeetingFixtures.northwind()
        let delay = DelayStats(median: 1.2, p90: 2.5, count: 40)
        loaded.meeting.timing = MeetingTiming(transcriptDelay: delay, summaryWaitSeconds: 10)
        try await harness.controller.open(harness.seed(loaded))
        await harness.waitFor(.state(.stopped))
        let current = try #require(loaded.meeting.summary)
        harness.summarizer.hold()

        let regenerating = Task { await harness.controller.regenerateSummary() }
        await harness.waitFor(isSummary(.rewriting(current)))
        harness.clock.advance(by: 2)
        harness.summarizer.release()
        await regenerating.value

        #expect(try harness.stored().meeting.timing == MeetingTiming(transcriptDelay: delay, summaryWaitSeconds: 2))
    }
}
