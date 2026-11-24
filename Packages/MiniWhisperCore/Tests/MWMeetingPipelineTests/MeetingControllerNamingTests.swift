import Foundation
import Testing

import MWConfig
@testable import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWSupport
import MWTestSupport
import MWTranscription
import MWUsage
import MWVoices

private let kate = RawSuggestion(
    speaker: "S1", name: "Kate Morgan", confidence: "certain", kind: "self_introduction", turn: 1,
    quote: "My name is Kate Morgan"
)
private let usage = TokenUsage(inputTokens: 1200, outputTokens: 90, cacheReadTokens: 300, cacheWriteTokens: 40)
private let found = FakeNameSuggester.Answer.reply(NamingReply(suggestions: [kate], usage: usage))

/// Live naming in a meeting (design §5 Control flow, Live meeting): the trigger, the R7 guards,
/// suggestions and auto-apply, billing, and the one-time and pause notices. The user is "Alex".
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MeetingControllerNamingTests {
    private func match(
        _ segment: Segment, state: NameMatch.State = .suggested
    ) -> NameMatch {
        NameMatch(
            key: "1:S1", name: "Kate Morgan", person: nil, source: "conversation", state: state,
            evidence: NameEvidence(segment: segment.id, time: segment.start, text: "My name is Kate Morgan"),
            kind: "self_introduction"
        )
    }

    // MARK: - Live suggestion (R5, R13)

    @Test func nameThenAnotherSpeakerSendsOneRequestAndSuggests() async throws {
        let sink = CapturingLogSink()
        let namer = FakeNameSuggester([found])
        let harness = try await MeetingHarness.withNamer(namer)

        try await logging(to: sink) {
            try await harness.start()
            try await harness.introduceKate()
            await harness.controller.waitForNaming()
        }

        #expect(namer.requests.count == 1)
        #expect(namer.requests.first?.blocks.joined().contains("T1 S1 [00:00]: My name is Kate Morgan.") == true)
        let introduction = try #require(try harness.stored().segments.first)
        let suggested = match(introduction)
        let speakers = await harness.waitForSpeakers { $0.first { $0.id == 1 }?.matches == [suggested] }
        #expect(speakers.first { $0.id == 1 }?.name == "Speaker 1")
        #expect(try harness.stored().meeting.speakers.first { $0.id == 1 }?.matches == [suggested])
        let naming = sink.records.filter { $0.category == "naming" }.map(\.message)
        #expect(!naming.isEmpty)
        for line in naming {
            for secret in ["Kate", "Morgan", "My name", "begin"] {
                #expect(!line.contains(secret), "\(line) leaks \(secret)")
            }
        }
    }

    // MARK: - Auto-apply (R22)

    @Test func selfIntroductionIsAppliedWithAutoApplyOn() async throws {
        let harness = try await MeetingHarness.withNamer(FakeNameSuggester([found])) { $0.meetingNamingAutoApply = true }

        try await harness.start()
        try await harness.introduceKate()
        await harness.controller.waitForNaming()

        let introduction = try #require(try harness.stored().segments.first)
        let speaker = try #require(try harness.stored().meeting.speakers.first { $0.id == 1 })
        #expect(speaker == SpeakerLabel(
            id: 1, name: "Kate Morgan", providerKeys: ["1:S1"], matches: [match(introduction, state: .applied)]
        ))
    }

    /// The People reader leaves the user out, and an applied name links and teaches no voice.
    @Test func peopleWithoutTheUserAreOfferedAndAnAppliedNameTeachesNoVoice() async throws {
        let namer = FakeNameSuggester([found])
        let harness = try await MeetingHarness(
            secrets: [.assemblyai: MeetingHarness.key, .speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key],
            voices: FakeVoiceEmbedder(),
            namer: namer
        ) {
            $0.meetingEngine = .assemblyaiPro
            $0.voice.localEnabled = true
            $0.meetingNamingAutoApply = true
        }
        try await harness.remember("Priya Shah", voice: .unit(3))
        try await harness.remember("Alex", voice: .unit(4), isUser: true)

        try await harness.start()
        try await harness.introduceKate()
        await harness.controller.waitForNaming()

        let state = try #require(namer.requests.first?.state)
        #expect(state.split(separator: "\n").contains("people: Priya Shah"))
        let speaker = try #require(try harness.stored().meeting.speakers.first { $0.id == 1 })
        #expect(speaker.name == "Kate Morgan")
        #expect(speaker.person == nil)
        #expect(await harness.voices?.store.people().map(\.name).sorted() == ["Alex", "Priya Shah"])
        #expect(try harness.matchLog().isEmpty)
    }

    // MARK: - No request (R7)

    @Test func testCallSendsNothing() async throws {
        let namer = FakeNameSuggester([found])
        let harness = try await MeetingHarness.withNamer(namer)
        let tag = TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")

        try await harness.controller.start(mode: .remote, title: "Test call · Sprint planning", test: tag)
        try await harness.introduceKate()
        await harness.controller.waitForNaming()

        #expect(namer.requests.isEmpty)
        #expect(!harness.seen.contains { if case .naming = $0 { true } else { false } })
    }

    @Test func switchOffSendsNothing() async throws {
        let namer = FakeNameSuggester([found])
        let harness = try await MeetingHarness.withNamer(namer) { $0.meetingNamingEnabled = false }

        try await harness.start()
        try await harness.introduceKate()
        await harness.controller.waitForNaming()

        #expect(namer.requests.isEmpty)
    }

    @Test func noAnthropicKeySendsNothing() async throws {
        let namer = FakeNameSuggester([found])
        let harness = try await MeetingHarness.withNamer(namer, anthropic: false)

        try await harness.start()
        try await harness.introduceKate()
        await harness.controller.waitForNaming()

        #expect(namer.requests.isEmpty)
    }

    @Test func everySpeakerNamedSendsNothing() async throws {
        let namer = FakeNameSuggester([found])
        let harness = try await MeetingHarness.withNamer(namer)

        try await harness.start()
        try await harness.say("Hello.", as: "S2", at: 0)
        try await harness.say("My name is Kate Morgan.", as: "S1", at: 3)
        await harness.controller.rename(speaker: 1, to: "Kate")
        await harness.controller.rename(speaker: 2, to: "Dan")
        try await harness.say("Shall we begin?", as: "S2", at: 6)
        await harness.controller.waitForNaming()

        #expect(namer.requests.isEmpty)
    }

    @Test func noNamerSendsNothing() async throws {
        let harness = try await MeetingHarness(secrets: [.speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key])

        try await harness.start()
        try await harness.introduceKate()
        await harness.controller.waitForNaming()
        _ = await harness.tick(to: 1)

        #expect(!harness.seen.contains { if case .naming = $0 { true } else { false } })
        #expect(harness.usage.added.isEmpty)
    }

    // MARK: - Switch off mid-flight (R4)

    @Test func replyAfterTheSwitchWentOffIsDroppedButBilled() async throws {
        let namer = FakeNameSuggester([found])
        namer.hold()
        let harness = try await MeetingHarness.withNamer(namer)
        let cost = Pricing.namingCost(usage, overrides: [:])

        try await harness.start()
        try await harness.introduceKate()
        await namer.waitForRequests()
        try await harness.config.update { @Sendable config in config.meetingNamingEnabled = false }
        namer.release()
        await harness.controller.waitForNaming()

        let stored = try harness.stored().meeting
        #expect(stored.speakers.allSatisfy { $0.matches.isEmpty && $0.name == SpeakerLabel.defaultName($0.id) || $0.isUser })
        #expect(stored.billing.namingCostUSD == cost)
        #expect(harness.usage.added.map(\.costUSD) == [cost])
    }

    // MARK: - Billing and cost (R28)

    @Test func eachRequestIsBilledAndShownInTheLiveCost() async throws {
        let overrides = ["claude-haiku-5-5_in": 2.0, "claude-haiku-5-5_out": 9.0]
        let harness = try await MeetingHarness.withNamer(FakeNameSuggester([found, found])) {
            $0.pricingOverrides = overrides
        }
        let cost = Pricing.namingCost(usage, overrides: overrides)

        try await harness.start()
        try await harness.introduceKate()
        await harness.controller.waitForNaming()
        await harness.waitFor(.cost(cost))
        try await harness.introduceKate(at: 10)
        await harness.controller.waitForNaming()
        await harness.waitFor(.cost(cost + cost))

        #expect(harness.controller.meeting?.billing.namingCostUSD == cost + cost)
        #expect(try harness.stored().meeting.billing.namingCostUSD == cost + cost)
        let billed = ProviderUsage(purpose: .naming, inputTokens: 1200 + 300 + 40, outputTokens: 90, costUSD: cost)
        #expect(harness.usage.added == [billed, billed])

        _ = await harness.tick(to: 1)
        let ticked = await harness.waitFor { if case .cost = $0 { true } else { false } }.last
        #expect(ticked == .cost(cost + cost))
    }

    // MARK: - One-time notice (R26)

    @Test func noticeIsShownOnceAndRemembered() async throws {
        let first = try await MeetingHarness.withNamer(FakeNameSuggester())
        try await first.start()
        _ = await first.tick(to: 1)

        #expect(first.seen.filter { $0 == .naming(.introduced) }.count == 1)
        #expect(await first.config.load().meetingNamingExplained)

        let second = try await MeetingHarness.withNamer(FakeNameSuggester()) { $0.meetingNamingExplained = true }
        try await second.start()
        _ = await second.tick(to: 1)

        #expect(!second.seen.contains(.naming(.introduced)))
    }

    @Test(arguments: ["switch off", "no key", "no namer"])
    func noNoticeWhileNamingCannotRun(_ reason: String) async throws {
        let harness = switch reason {
        case "switch off": try await MeetingHarness.withNamer(FakeNameSuggester()) { $0.meetingNamingEnabled = false }
        case "no key": try await MeetingHarness.withNamer(FakeNameSuggester(), anthropic: false)
        default: try await MeetingHarness(secrets: [.speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key])
        }

        try await harness.start()
        _ = await harness.tick(to: 1)

        #expect(!harness.seen.contains(.naming(.introduced)))
        #expect(await harness.config.load().meetingNamingExplained == false)
    }

    // MARK: - Pause (R27)

    @Test func threeFailuresPauseWithANoticeAndStopRequests() async throws {
        let namer = FakeNameSuggester([
            .failure(NamingError.rateLimited),
            .failure(NamingError.server(503)),
            .failure(NamingError.transport("no internet connection")),
        ])
        let harness = try await MeetingHarness.withNamer(namer)

        try await harness.start()
        for round in 0..<3 {
            try await harness.introduceKate(at: Double(round) * 10)
            await harness.controller.waitForNaming()
        }
        await harness.waitFor(.naming(.paused("no internet connection")))
        try await harness.introduceKate(at: 30)
        await harness.controller.waitForNaming()

        #expect(namer.requests.count == 3)
        #expect(harness.seen.filter { if case .naming(.paused) = $0 { true } else { false } }.count == 1)
    }

    // MARK: - Follow-up (R6)

    @Test func firesDuringAFlightSendExactlyOneFollowUp() async throws {
        let namer = FakeNameSuggester()
        namer.hold()
        let harness = try await MeetingHarness.withNamer(namer)

        try await harness.start()
        try await harness.introduceKate()
        await namer.waitForRequests()
        try await harness.introduceKate(at: 10)
        try await harness.introduceKate(at: 20)
        namer.release()
        await harness.controller.waitForNaming()

        #expect(namer.requests.count == 2)
        #expect(namer.requests.last?.blocks.joined().contains("T6 S2 [00:23]: Shall we begin?") == true)
    }
}

extension MeetingHarness {
    /// A Speechmatics meeting with naming's fake client, and an Anthropic key unless `anthropic` is false.
    static func withNamer(
        _ namer: FakeNameSuggester,
        anthropic: Bool = true,
        _ configure: @escaping @Sendable (inout Config) -> Void = { _ in }
    ) async throws -> MeetingHarness {
        var secrets: [KeyAccount: String] = [.speechmatics: key]
        if anthropic { secrets[.anthropic] = key }
        return try await MeetingHarness(secrets: secrets, namer: namer, configure)
    }

    /// One final segment from provider speaker `label` on session 1, once added.
    func say(_ text: String, as label: String, at start: Double) async throws {
        try sink(1).onSegment(TranscriptSegment(text: text, speaker: label, start: start, end: start + 2))
        await waitFor { if case .segmentAdded(let segment) = $0 { segment.start == start } else { false } }
    }

    /// S1 names itself, then S2 speaks: one fire of the trigger.
    func introduceKate(at start: Double = 0) async throws {
        try await say("My name is Kate Morgan.", as: "S1", at: start)
        try await say("Shall we begin?", as: "S2", at: start + 3)
    }
}
