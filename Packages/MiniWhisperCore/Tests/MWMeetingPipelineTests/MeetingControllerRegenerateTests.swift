import Foundation
import Testing

import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWSupport
import MWTestSupport
import MWTranscription
import MWUsage

/// Regenerate (design §5.6): the stored summary stays current until a new one has arrived.
///
/// No test waits twice for a summary event without checking the first: a wait after the
/// terminal event never returns.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MeetingControllerRegenerateTests {
    private static let keys: [KeyAccount: String] = [
        .speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key,
    ]
    private static let reply = SummaryResult(
        text: "## Rollout\n\n- Ships on Friday.", usage: TokenUsage(inputTokens: 1200, outputTokens: 300)
    )

    /// The summary a reply becomes for the Northwind meeting, at the harness's wall time.
    private static func summary(of reply: SummaryResult = reply) -> Summary {
        Summary(
            text: reply.text,
            model: AnthropicClient.model,
            createdAt: MeetingHarness.wallStart,
            inputTokens: reply.usage.inputTokens,
            outputTokens: reply.usage.outputTokens,
            costUSD: Pricing.meetingCost(engine: .speechmaticsStandard, seconds: 0, tokens: reply.usage, overrides: [:])
        )
    }

    /// A stored meeting, opened, with the events of opening it already pulled.
    private func opened(
        _ loaded: LoadedMeeting = MeetingFixtures.northwind(),
        secrets: [KeyAccount: String] = keys,
        summarizer: FakeSummarizer = FakeSummarizer(result: reply)
    ) async throws -> MeetingHarness {
        let harness = try await MeetingHarness(secrets: secrets, summarizer: summarizer)
        try await harness.controller.open(harness.seed(loaded))
        await harness.waitFor(.state(.stopped))
        return harness
    }

    private static func isSummary(_ event: MeetingEvent) -> Bool {
        if case .summary = event { true } else { false }
    }

    /// The summary event a request ends with.
    private static func isTerminal(_ event: MeetingEvent) -> Bool {
        switch event {
        case .summary(.writing), .summary(.rewriting): false
        case .summary: true
        default: false
        }
    }

    // MARK: - A new summary

    @Test func regenerateWritesANewSummaryAndKeepsTheOldOneCurrentMeanwhile() async throws {
        let harness = try await opened()
        let old = try #require(harness.controller.meeting?.summary)
        let new = Self.summary()
        harness.summarizer.hold()

        let request = Task { await harness.controller.regenerateSummary() }
        let first = await harness.nextSummary()
        #expect(harness.controller.meeting?.summary == old)
        #expect(try harness.stored().meeting.summary == old)
        #expect(harness.usage.added.isEmpty)
        harness.summarizer.release()
        await request.value

        try #require(first == .rewriting(old))
        #expect(await harness.nextSummary() == .ready(new))
        let stored = try harness.stored().meeting
        #expect(stored.summary == new)
        #expect(stored.billing == Billing(engineSeconds: 2932, costUSD: 0.3665, replacedSummaryCostUSD: old.costUSD))
        #expect(stored.totalCostUSD == 0.3665 + old.costUSD + new.costUSD)
        #expect(stored == harness.controller.meeting)
        #expect(harness.usage.added == [ProviderUsage(inputTokens: 1200, outputTokens: 300, costUSD: new.costUSD)])
        #expect(harness.summarizer.calls.count == 1)
    }

    @Test func regeneratingTwiceAddsEachReplacedCostAndLogsNoSummaryText() async throws {
        let second = SummaryResult(
            text: "## Pricing\n\n- The cap is 25 seats.", usage: TokenUsage(inputTokens: 900, outputTokens: 150)
        )
        let sink = CapturingLogSink()
        let harness = try await opened(summarizer: FakeSummarizer(queue: [Self.reply, second]))
        let old = try #require(harness.controller.meeting?.summary)

        try await logging(to: sink) {
            await harness.controller.regenerateSummary()
            await harness.controller.regenerateSummary()
        }

        let first = Self.summary(), last = Self.summary(of: second)
        try #require(await harness.waitFor(Self.isTerminal) == [.summary(.rewriting(old)), .summary(.ready(first))])
        #expect(await harness.waitFor(Self.isTerminal) == [.summary(.rewriting(first)), .summary(.ready(last))])
        let stored = try harness.stored().meeting
        #expect(stored.summary == last)
        #expect(stored.billing.replacedSummaryCostUSD == old.costUSD + first.costUSD)
        #expect(harness.usage.added.map(\.costUSD) == [first.costUSD, last.costUSD])

        // A later save keeps the replaced cost.
        await harness.controller.retitle("Northwind sync")
        #expect(try harness.stored().meeting.billing.replacedSummaryCostUSD == old.costUSD + first.costUSD)

        #expect(sink.lines == [
            "INFO meeting summary regenerate started", "INFO meeting summary regenerate: ready",
            "INFO meeting summary regenerate started", "INFO meeting summary regenerate: ready",
        ])
        Self.expectNoSummaryText(in: sink, of: [old, first, last])
    }

    // MARK: - The summary kept

    @Test func regenerateWithoutAKeyKeepsTheSummary() async throws {
        let harness = try await opened(secrets: [.speechmatics: MeetingHarness.key])
        let old = try #require(harness.controller.meeting?.summary)
        let before = try harness.meetingJSON()

        await harness.controller.regenerateSummary()

        let events = await harness.waitFor(Self.isTerminal)
        #expect(events == [.summary(.kept(old, reason: "No summary: add an Anthropic key under Keys."))])
        #expect(try harness.meetingJSON() == before)
        #expect(harness.usage.added.isEmpty)
        #expect(harness.summarizer.calls.isEmpty)
    }

    @Test func regenerateWithNothingTranscribedKeepsTheSummary() async throws {
        var silent = MeetingFixtures.northwind()
        silent.segments = []
        let harness = try await opened(silent)
        let old = try #require(harness.controller.meeting?.summary)
        let before = try harness.meetingJSON()

        await harness.controller.regenerateSummary()

        let events = await harness.waitFor(Self.isTerminal)
        #expect(events == [.summary(.kept(old, reason: "Nothing was transcribed."))])
        #expect(try harness.meetingJSON() == before)
        #expect(harness.usage.added.isEmpty)
        #expect(harness.summarizer.calls.isEmpty)
    }

    @Test func regenerateDeclinedKeepsTheSummary() async throws {
        let harness = try await opened(
            summarizer: FakeSummarizer(result: SummaryResult(text: "", refusalCategory: "cyber"))
        )
        let old = try #require(harness.controller.meeting?.summary)
        let before = try harness.meetingJSON()

        await harness.controller.regenerateSummary()

        let events = await harness.waitFor(Self.isTerminal)
        #expect(events == [.summary(.rewriting(old)), .summary(.kept(old, reason: "Summary declined (cyber)"))])
        #expect(try harness.meetingJSON() == before)
        #expect(harness.controller.meeting?.summary == old)
        #expect(harness.usage.added.isEmpty)
    }

    @Test func regenerateFailureKeepsTheSummaryAndLogsTheReasonOnly() async throws {
        let sink = CapturingLogSink()
        let harness = try await opened(summarizer: FakeSummarizer(failure: APIError.httpStatus(503)))
        let old = try #require(harness.controller.meeting?.summary)
        let before = try harness.meetingJSON()

        try await logging(to: sink) { await harness.controller.regenerateSummary() }

        let events = await harness.waitFor(Self.isTerminal)
        #expect(events == [.summary(.rewriting(old)), .summary(.kept(old, reason: "API error (503)."))])
        #expect(try harness.meetingJSON() == before)
        #expect(harness.controller.meeting?.summary == old)
        #expect(harness.usage.added.isEmpty)
        #expect(sink.lines == [
            "INFO meeting summary regenerate started",
            "WARNING meeting summary failed: API error (503).",
            "INFO meeting summary regenerate: kept (API error (503).)",
        ])
        Self.expectNoSummaryText(in: sink, of: [old])
    }

    // MARK: - Refused calls

    @Test func regenerateIsANoOpWithoutASummaryOrBeforeStop() async throws {
        var unsummarised = MeetingFixtures.northwind()
        unsummarised.meeting.summary = nil
        let stored = try await opened(unsummarised)
        let live = try await MeetingHarness(secrets: Self.keys)
        try await live.start(.inRoom)
        try await live.deliverSegment()

        await stored.controller.regenerateSummary()
        await live.controller.regenerateSummary()

        // A later event shows whether a summary event came first.
        await stored.controller.rename(speaker: 0, to: "Sam")
        await live.controller.stop(summarise: false)
        let afterStored = await stored.waitFor { if case .speakers = $0 { true } else { false } }
        let afterLive = await live.waitFor(.state(.stopped))
        #expect(!afterStored.contains(where: Self.isSummary))
        #expect(!afterLive.contains(where: Self.isSummary))
        #expect(stored.summarizer.calls.isEmpty)
        #expect(live.summarizer.calls.isEmpty)
    }

    @Test func aSecondRegenerateWhileOneIsInFlightReturns() async throws {
        let harness = try await opened()
        let old = try #require(harness.controller.meeting?.summary)
        harness.summarizer.hold()

        let request = Task { await harness.controller.regenerateSummary() }
        let first = await harness.nextSummary()
        await harness.controller.regenerateSummary()
        harness.summarizer.release()
        await request.value

        try #require(first == .rewriting(old))
        // The second call's event, had it emitted one, would come before this.
        #expect(await harness.nextSummary() == .ready(Self.summary()))
        #expect(harness.summarizer.calls.count == 1)
        #expect(harness.usage.added.count == 1)
        #expect(try harness.stored().meeting.billing.replacedSummaryCostUSD == old.costUSD)
    }

    @Test func summariseAndRegenerateDoNotOverlap() async throws {
        // Summarise during a regenerate.
        let regenerating = try await opened()
        let old = try #require(regenerating.controller.meeting?.summary)
        regenerating.summarizer.hold()
        let regenerate = Task { await regenerating.controller.regenerateSummary() }
        let rewriting = await regenerating.nextSummary()
        await regenerating.controller.summarise()
        regenerating.summarizer.release()
        await regenerate.value

        try #require(rewriting == .rewriting(old))
        #expect(await regenerating.nextSummary() == .ready(Self.summary()))
        #expect(regenerating.summarizer.calls.count == 1)

        // Regenerate, and Summarise again, during a first summary.
        var unsummarised = MeetingFixtures.northwind()
        unsummarised.meeting.summary = nil
        let summarising = try await opened(unsummarised)
        summarising.summarizer.hold()
        let summarise = Task { await summarising.controller.summarise() }
        let writing = await summarising.nextSummary()
        await summarising.controller.regenerateSummary()
        await summarising.controller.summarise()
        summarising.summarizer.release()
        await summarise.value

        try #require(writing == .writing)
        #expect(await summarising.nextSummary() == .ready(Self.summary()))
        #expect(summarising.summarizer.calls.count == 1)
        #expect(try summarising.stored().meeting.billing.replacedSummaryCostUSD == 0)
    }

    /// R27: no line of a summary reaches a log.
    private static func expectNoSummaryText(in sink: CapturingLogSink, of summaries: [Summary]) {
        let phrases = summaries.flatMap { $0.text.split(whereSeparator: \.isNewline) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        #expect(!phrases.isEmpty)
        for line in sink.lines {
            #expect(!phrases.contains { line.contains($0) }, "\(line)")
        }
    }
}

private extension MeetingHarness {
    /// The next summary event's state.
    func nextSummary() async -> SummaryState? {
        guard case .summary(let state)? = await waitFor({ if case .summary = $0 { true } else { false } }).last
        else { return nil }
        return state
    }

    func meetingJSON() throws -> Data {
        let id = try #require(controller.meeting?.id)
        return try Data(contentsOf: store.directory.appendingPathComponent(id.uuidString).appendingPathComponent("meeting.json"))
    }
}
