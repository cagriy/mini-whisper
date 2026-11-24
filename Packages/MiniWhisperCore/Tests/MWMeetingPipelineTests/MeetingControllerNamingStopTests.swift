import Foundation
import Testing

import MWConfig
@testable import MWMeetingPipeline
import MWMeetings
import MWSupport
import MWTestSupport
import MWTranscription
import MWUsage

private let kate = RawSuggestion(
    speaker: "S1", name: "Kate Morgan", confidence: "certain", kind: "self_introduction", turn: 1,
    quote: "My name is Kate Morgan"
)
private let usage = TokenUsage(inputTokens: 1200, outputTokens: 90, cacheReadTokens: 300, cacheWriteTokens: 40)
private let found = FakeNameSuggester.Answer.reply(NamingReply(suggestions: [kate], usage: usage))
private let cost = Pricing.namingCost(usage, overrides: [:])
/// Three failures in a row pause live naming; the last gives the reason.
private let pausing: [FakeNameSuggester.Answer] = [
    .failure(NamingError.rateLimited),
    .failure(NamingError.server(503)),
    .failure(NamingError.transport("no internet connection")),
]

/// The Stop pass and Suggest names (design §5 Control flow: Stop, Stored meeting, Suggest names):
/// naming cost across Stop, the wait for the live request, the order against the summary, the
/// results and the guards (R7, R11, R25, R28). The user is "Alex".
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MeetingControllerNamingStopTests {
    private static let introduction = Segment(
        id: UUID(uuidString: "5e1f0000-0000-4000-8000-000000000001")!, speaker: 1, start: 0, end: 2,
        text: "My name is Kate Morgan.", session: 1, providerLabel: "S1"
    )

    /// A past meeting in which Speaker 1 introduced themselves, with engine, replaced summary and
    /// naming costs already billed.
    private static func stored(test: TestCallTag? = nil, speaker name: String = "Speaker 1") -> LoadedMeeting {
        var loaded = MeetingFixtures.make(segments: [introduction], test: test)
        loaded.meeting.speakers.append(SpeakerLabel(id: 1, name: name, providerKeys: ["1:S1"]))
        loaded.meeting.billing = Billing(engineSeconds: 60, costUSD: 0.5, replacedSummaryCostUSD: 0.25, namingCostUSD: 0.125)
        return loaded
    }

    private static func suggested(_ segment: Segment) -> NameMatch {
        NameMatch(
            key: "1:S1", name: "Kate Morgan", person: nil, source: "conversation", state: .suggested,
            evidence: NameEvidence(segment: segment.id, time: segment.start, text: "My name is Kate Morgan"),
            kind: "self_introduction"
        )
    }

    // MARK: - Billing (R28, design §7)

    @Test func liveNamingCostSurvivesStop() async throws {
        let harness = try await MeetingHarness.withNamer(FakeNameSuggester([found]))
        try await harness.start()
        harness.feed(MeetingHarness.quiet(1))
        try await harness.introduceKate()
        await harness.controller.waitForNaming()

        await harness.controller.stop(summarise: false)

        var engine = MeetingBilling(engine: .speechmaticsStandard, overrides: [:])
        for _ in 0..<10 { engine.add(seconds: 0.1) }
        var billing = engine.totals
        billing.namingCostUSD = cost
        #expect(try harness.stored().meeting.billing == billing)
        #expect(harness.controller.meeting?.billing == billing)
    }

    // MARK: - After the in-flight request (R11)

    @Test func stopWaitsForTheLiveRequestDropsItsFollowUpAndSendsOnePass() async throws {
        let sink = CapturingLogSink()
        let namer = FakeNameSuggester([found])
        namer.hold()
        let harness = try await MeetingHarness.withNamer(namer)

        try await logging(to: sink) {
            try await harness.start()
            try await harness.introduceKate()
            await namer.waitForRequests()
            // During the flight: a fire, kept as a follow-up, then a name that arms the trigger.
            try await harness.introduceKate(at: 10)
            try await harness.say("My name is Kate Morgan.", as: "S1", at: 20)
            let stop = Task { await harness.controller.stop() }
            await harness.waitFor(.naming(.running))
            #expect(namer.requests.count == 1)
            namer.release()
            await stop.value
            await harness.controller.waitForNaming()
        }

        #expect(namer.requests.count == 2)
        let pass = try #require(namer.requests.last)
        #expect(pass.blocks.joined().contains("T5 S1 [00:20]: My name is Kate Morgan."))
        // Sent after the live reply was applied.
        #expect(pass.state.split(separator: "\n").contains("S1: suggested Kate Morgan"))
        let scopes = sink.records.filter { $0.category == "naming" && $0.message.contains(" request: ") }
            .map { String($0.message.prefix { $0 != " " }) }
        #expect(scopes == ["live", "stop"])
        await harness.waitFor(.naming(.finished(.none)))
    }

    // MARK: - Order against the summary (R11)

    @Test func withAutoApplyTheSummaryWaitsForThePassAndSeesTheAppliedName() async throws {
        let harness = try await MeetingHarness.withNamer(FakeNameSuggester([found])) { $0.meetingNamingAutoApply = true }
        try await harness.start()
        try await harness.say("My name is Kate Morgan.", as: "S1", at: 0)

        await harness.controller.stop()

        let events = await harness.waitFor { if case .summary(.ready) = $0 { true } else { false } }
        let order: [MeetingEvent] = [.naming(.running), .naming(.finished(.found(1))), .summary(.writing)]
        #expect(events.filter(order.contains) == order)
        let user = try #require(harness.summarizer.calls.first?.user)
        #expect(user.hasPrefix("Speakers: Kate Morgan\n"))
    }

    @Test func withoutAutoApplyThePassAndTheSummaryRunTogether() async throws {
        let namer = FakeNameSuggester([found])
        namer.hold()
        let harness = try await MeetingHarness.withNamer(namer)
        harness.summarizer.hold()
        try await harness.start()
        try await harness.say("My name is Kate Morgan.", as: "S1", at: 0)

        let stop = Task { await harness.controller.stop() }
        await namer.waitForRequests()
        harness.summarizer.release()
        // Stop returns with the summary while the pass is still held.
        await stop.value

        let summarised = await harness.waitFor { if case .summary(.ready) = $0 { true } else { false } }
        #expect(summarised.contains(.naming(.running)))
        #expect(!summarised.contains { if case .naming(.finished) = $0 { true } else { false } })
        #expect(harness.summarizer.calls.count == 1)
        namer.release()
        await harness.waitFor(.naming(.finished(.found(1))))
    }

    // MARK: - No pass (R7, R11)

    @Test(arguments: ["quit", "paused", "no open speaker", "switch off", "no key"])
    func stopRunsNoPass(_ reason: String) async throws {
        let namer = FakeNameSuggester(reason == "paused" ? pausing : [], otherwise: found)
        let harness = switch reason {
        case "switch off": try await MeetingHarness.withNamer(namer) { $0.meetingNamingEnabled = false }
        case "no key": try await MeetingHarness.withNamer(namer, anthropic: false)
        default: try await MeetingHarness.withNamer(namer)
        }
        try await harness.start()
        if reason == "paused" { try await harness.pauseNaming() }
        try await harness.say("My name is Kate Morgan.", as: "S1", at: 40)
        if reason == "no open speaker" { await harness.controller.rename(speaker: 1, to: "Kate") }
        let sent = namer.requests.count

        await harness.controller.stop(summarise: reason != "quit")

        #expect(!(await harness.eventsUntilNote()).contains(.naming(.running)))
        await harness.controller.waitForNaming()
        #expect(namer.requests.count == sent)
    }

    // MARK: - Stop-pass results (R11, Planning decision 2)

    @Test(arguments: ["found", "none", "failed"])
    func stopPassEndsWithItsResult(_ outcome: String) async throws {
        let sink = CapturingLogSink()
        let (answer, result, billed): (FakeNameSuggester.Answer, NamingResult, Double) = switch outcome {
        case "found": (found, .found(1), cost)
        case "none": (.reply(NamingReply(suggestions: [], usage: usage)), .none, cost)
        default: (.failure(NamingError.rateLimited), .failed("Anthropic is rate-limiting requests"), 0)
        }
        let harness = try await MeetingHarness.withNamer(FakeNameSuggester([answer]))

        try await logging(to: sink) {
            try await harness.start()
            try await harness.say("My name is Kate Morgan.", as: "S1", at: 0)
            await harness.controller.stop()
            await harness.controller.waitForNaming()
        }

        let events = await harness.waitFor(.naming(.finished(result)))
        let running = try #require(events.firstIndex(of: .naming(.running)))
        #expect(events[running...].filter { if case .cost = $0 { true } else { false } } == [.cost(billed)])
        let stored = try harness.stored()
        #expect(stored.meeting.billing.namingCostUSD == billed)
        let matches = try #require(stored.meeting.speakers.first { $0.id == 1 }).matches
        #expect(matches == (outcome == "found" ? [Self.suggested(stored.segments[0])] : []))
        let failures = sink.records.filter { $0.category == "naming" && $0.message.hasPrefix("stop failed after ") }
        #expect(failures.count == (outcome == "failed" ? 1 : 0))
    }

    // MARK: - Suggest names (R25)

    @Test func suggestNamesOnAStoredMeetingRunsWithTheSwitchOff() async throws {
        let namer = FakeNameSuggester([found])
        // Applying needs both switches on, so this stays a suggestion.
        let harness = try await MeetingHarness.withNamer(namer) {
            $0.meetingNamingEnabled = false
            $0.meetingNamingAutoApply = true
        }
        try await harness.openStored(Self.stored())

        await harness.controller.suggestNames()

        let events = await harness.waitFor(.naming(.finished(.found(1))))
        let shown = events.filter { if case .naming = $0 { true } else if case .cost = $0 { true } else { false } }
        #expect(shown == [.naming(.running), .cost(0.5 + 0.25 + (0.125 + cost)), .naming(.finished(.found(1)))])
        #expect(namer.requests.count == 1)
        let stored = try harness.stored().meeting
        #expect(stored.speakers.last == SpeakerLabel(
            id: 1, name: "Speaker 1", providerKeys: ["1:S1"], matches: [Self.suggested(Self.introduction)]
        ))
        #expect(stored.billing.namingCostUSD == 0.125 + cost)
        #expect(harness.usage.added == [
            ProviderUsage(purpose: .naming, inputTokens: 1200 + 300 + 40, outputTokens: 90, costUSD: cost),
        ])
    }

    @Test func suggestNamesRunsAfterLiveNamingPaused() async throws {
        let namer = FakeNameSuggester(pausing + [found])
        let harness = try await MeetingHarness.withNamer(namer)
        try await harness.start()
        try await harness.pauseNaming()
        await harness.controller.stop()

        await harness.controller.suggestNames()

        let events = await harness.waitFor(.naming(.finished(.found(1))))
        #expect(events.filter { $0 == .naming(.running) }.count == 1)
        #expect(namer.requests.count == 4)
    }

    @Test(arguments: ["test call", "no key", "no open speaker", "recording"])
    func suggestNamesSendsNothing(_ reason: String) async throws {
        let namer = FakeNameSuggester([found])
        let harness = try await MeetingHarness.withNamer(namer, anthropic: reason != "no key")
        switch reason {
        case "test call":
            let tag = TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")
            try await harness.openStored(Self.stored(test: tag))
        case "no open speaker": try await harness.openStored(Self.stored(speaker: "Kate"))
        case "recording":
            try await harness.start()
            try await harness.say("My name is Kate Morgan.", as: "S1", at: 0)
        default: try await harness.openStored(Self.stored())
        }

        await harness.controller.suggestNames()

        #expect(!(await harness.eventsUntilNote()).contains(.naming(.running)))
        #expect(namer.requests.isEmpty)
    }

    @Test func suggestNamesWhileARequestRunsSendsNothingMore() async throws {
        let namer = FakeNameSuggester([found])
        namer.hold()
        let harness = try await MeetingHarness.withNamer(namer)
        try await harness.openStored(Self.stored())

        let first = Task { await harness.controller.suggestNames() }
        await namer.waitForRequests()
        await harness.controller.suggestNames()
        namer.release()
        await first.value

        let events = await harness.waitFor(.naming(.finished(.found(1))))
        #expect(events.filter { $0 == .naming(.running) }.count == 1)
        #expect(namer.requests.count == 1)
    }
}

private extension MeetingHarness {
    func openStored(_ loaded: LoadedMeeting) async throws {
        try await controller.open(seed(loaded))
        await waitFor(.state(.stopped))
    }

    /// Three failed live requests in a row, answered by `pausing`: live naming pauses.
    func pauseNaming() async throws {
        for round in 0..<3 {
            try await introduceKate(at: Double(round) * 10)
            await controller.waitForNaming()
        }
        await waitFor(.naming(.paused("no internet connection")))
    }

    /// Every event up to a note added now, so everything emitted before this call.
    func eventsUntilNote() async -> [MeetingEvent] {
        await controller.addNote("Checked.", firstKeystrokeAt: 0)
        return await waitFor { if case .note = $0 { true } else { false } }
    }
}
