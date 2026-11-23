import Foundation
import MWMeetings
import MWNaming
import MWSupport
import MWTestSupport
import MWTranscription
import MWUsage
import Testing

@testable import MWMeetingPipeline

@MainActor
@Suite struct MeetingNamingRouteTests {
    private let clock = VirtualClock()

    private static func segment(_ speaker: Int, _ start: Double, _ text: String) -> Segment {
        Segment(speaker: speaker, start: start, end: start + 2, text: text, session: 1)
    }

    private let introduction = segment(1, 0, "Hi, I'm Kate Morgan.")
    private let answer = segment(2, 4, "Welcome. Shall we start?")

    private static func label(_ id: Int, name: String? = nil) -> SpeakerLabel {
        SpeakerLabel(id: id, name: name ?? SpeakerLabel.defaultName(id), isUser: id == 0, providerKeys: ["1:S\(id)"])
    }

    private let speakers = [label(0, name: "Niamh"), label(1), label(2)]

    private func route(
        _ client: FakeNameSuggester,
        people: [(id: UUID, name: String)] = [],
        overrides: [String: Double] = [:]
    ) -> MeetingNamingRoute {
        MeetingNamingRoute(client: client, people: { people }, clock: clock, overrides: overrides)
    }

    private func snapshot(_ scope: NamingScope = .live, speakers: [SpeakerLabel]? = nil) -> NamingSnapshot {
        NamingSnapshot(
            scope: scope, segments: [introduction, answer], speakers: speakers ?? self.speakers,
            userName: "Niamh", mode: .remote, aliases: ["Neve"]
        )
    }

    private func context(speakers: [SpeakerLabel]? = nil) -> PolicyContext {
        PolicyContext(
            speakers: speakers ?? self.speakers, people: [], userName: "Niamh", aliases: ["Neve"], mode: .remote,
            autoApply: false, segmentSpeakers: [introduction.id: 1, answer.id: 2]
        )
    }

    private static let usage = TokenUsage(inputTokens: 1200, outputTokens: 90, cacheReadTokens: 300, cacheWriteTokens: 40)

    private static let kate = RawSuggestion(
        speaker: "S1", name: "Kate Morgan", confidence: "certain", kind: "self_introduction", turn: 1,
        quote: "I'm Kate Morgan"
    )

    private static func reply(_ suggestions: [RawSuggestion] = [kate]) -> FakeNameSuggester.Answer {
        .reply(NamingReply(suggestions: suggestions, usage: usage))
    }

    private func run(_ route: MeetingNamingRoute, _ scope: NamingScope = .live) async -> NamingOutcome {
        await route.run(snapshot: snapshot(scope)) { context() }
    }

    // MARK: - Trigger

    @Test func nameThenAnotherSpeakerFires() {
        let route = route(FakeNameSuggester())

        #expect(!route.segmentsAdded([introduction], speakers: speakers, known: ["Kate"]))
        #expect(route.segmentsAdded([answer], speakers: speakers, known: []))
        #expect(!route.segmentsAdded([Self.segment(1, 8, "Yes.")], speakers: speakers, known: []))
    }

    @Test func oneCallCanArmAndFire() {
        let route = route(FakeNameSuggester())

        #expect(route.segmentsAdded([introduction, answer], speakers: speakers, known: ["Kate"]))
    }

    @Test func tickFiresTwentySecondsAfterArming() {
        let route = route(FakeNameSuggester())

        _ = route.segmentsAdded([introduction], speakers: speakers, known: ["Kate"])

        #expect(!route.tick(at: 21.9))
        #expect(route.tick(at: 22))
    }

    /// NLTagger does not tag a lower-case name, so only a known name arms here.
    @Test func peopleExtrasAndStandingSuggestionsAreKnownNames() async {
        let quiet = Self.segment(1, 0, "niamh can you hear me")
        let next = Self.segment(2, 4, "Yes.")

        let unknown = route(FakeNameSuggester())
        #expect(!unknown.segmentsAdded([quiet, next], speakers: speakers, known: []))

        let people = route(FakeNameSuggester(), people: [(id: UUID(), name: "Niamh")])
        await people.reloadPeople()
        #expect(people.segmentsAdded([quiet, next], speakers: speakers, known: []))

        let extras = route(FakeNameSuggester())
        #expect(extras.segmentsAdded([quiet, next], speakers: speakers, known: ["Niamh"]))

        var suggested = speakers
        suggested[2].matches = [NameMatch(
            key: "1:S2", name: "Niamh", person: nil, source: "conversation", state: .suggested
        )]
        let standing = route(FakeNameSuggester())
        #expect(standing.segmentsAdded([quiet, next], speakers: suggested, known: []))
    }

    // MARK: - Run

    @Test func runSendsOneRequestFromTheSnapshotAndDecidesAgainstTheContext() async throws {
        let client = FakeNameSuggester([Self.reply()])
        let route = route(client, people: [(id: UUID(), name: "Dan")])
        var asked = 0

        let outcome = await route.run(snapshot: snapshot()) {
            asked += 1
            #expect(client.requests.count == 1, "the context is read after the reply")
            return context()
        }

        let expected = NamingPrompt.request(
            NamingTranscript.render(segments: [introduction, answer]),
            state: NamingState(
                speakers: speakers.map(SpeakerState.init), people: ["Dan"], userName: "Niamh", aliases: ["Neve"],
                mode: .remote
            )
        )
        #expect(client.requests == [expected])
        #expect(asked == 1)
        let evidence = NameEvidence(segment: introduction.id, time: 0, text: "I'm Kate Morgan")
        #expect(outcome.actions == [.suggest(speaker: 1, NameMatch(
            key: "1:S1", name: "Kate Morgan", person: nil, source: "conversation", state: .suggested,
            evidence: evidence, kind: "self_introduction"
        ))])
        #expect(outcome.usage == Self.usage)
        #expect(outcome.cost == Pricing.namingCost(Self.usage, overrides: [:]))
        #expect(outcome.cost > 0)
        #expect(outcome.failure == nil)
        #expect(outcome.pause == nil)
        #expect(!outcome.followUp)
    }

    @Test func currentSpeakersDecide() async {
        let route = route(FakeNameSuggester([Self.reply()]))
        var named = speakers
        named[1].name = "Bob"

        let outcome = await route.run(snapshot: snapshot()) { context(speakers: named) }

        #expect(outcome.actions.isEmpty)
        #expect(outcome.usage == Self.usage)
    }

    @Test func costHonoursOverrides() async {
        let overrides = ["claude-haiku-5-5_in": 2.0, "claude-haiku-5-5_out": 9.0]
        let route = route(FakeNameSuggester([Self.reply()]), overrides: overrides)

        let outcome = await run(route)

        #expect(outcome.cost == Pricing.namingCost(Self.usage, overrides: overrides))
        #expect(outcome.cost != Pricing.namingCost(Self.usage, overrides: [:]))
    }

    @Test func nilContextDropsTheReplyButKeepsItsCost() async {
        let route = route(FakeNameSuggester([Self.reply()]))

        let outcome = await route.run(snapshot: snapshot()) { nil }

        #expect(outcome.actions.isEmpty)
        #expect(outcome.usage == Self.usage)
        #expect(outcome.cost == Pricing.namingCost(Self.usage, overrides: [:]))
        #expect(outcome.failure == nil)
    }

    // MARK: - Single flight

    @Test func fireDuringAFlightFollowsUpOnce() async {
        let client = FakeNameSuggester()
        client.hold()
        let route = route(client)

        let flight = Task { await run(route) }
        await client.waitForRequests()
        #expect(!route.segmentsAdded([introduction, answer], speakers: speakers, known: ["Kate"]))
        #expect(!route.segmentsAdded([Self.segment(1, 8, "Kate again."), Self.segment(2, 9, "Yes.")], speakers: speakers, known: ["Kate"]))
        client.release()

        #expect(await flight.value.followUp)
        #expect(await run(route).followUp == false)
    }

    @Test func disarmDropsAnArmedTriggerAndAPendingFollowUp() async {
        let client = FakeNameSuggester()
        let route = route(client)

        _ = route.segmentsAdded([introduction], speakers: speakers, known: ["Kate"])
        route.disarm()
        #expect(!route.segmentsAdded([answer], speakers: speakers, known: []))
        #expect(!route.tick(at: 100))

        client.hold()
        let flight = Task { await run(route) }
        await client.waitForRequests()
        _ = route.segmentsAdded([introduction, answer], speakers: speakers, known: ["Kate"])
        route.disarm()
        client.release()

        #expect(await flight.value.followUp == false)
    }

    // MARK: - Failures

    @Test func unauthorizedPausesAtOnce() async {
        let client = FakeNameSuggester([.failure(NamingError.unauthorized)])
        let route = route(client)

        let outcome = await run(route)

        #expect(outcome.failure == .unauthorized)
        #expect(outcome.pause == .unauthorized)
        #expect(outcome.usage == nil)
        #expect(outcome.cost == 0)
        #expect(route.isPaused)

        let skipped = await run(route)
        #expect(client.requests.count == 1)
        #expect(skipped.actions.isEmpty)
        #expect(skipped.failure == nil)
        #expect(skipped.pause == nil)
        #expect(await run(route, .stop).failure == nil)
        #expect(client.requests.count == 1)
    }

    @Test func threeFailuresInARowPauseWithTheThirdsReason() async {
        let route = route(FakeNameSuggester([
            .failure(NamingError.rateLimited),
            .failure(NamingError.server(503)),
            .failure(NamingError.transport("no internet connection")),
        ]))

        let first = await run(route)
        let second = await run(route)
        #expect(first.failure == .rateLimited)
        #expect(second.failure == .server(503))
        #expect(first.pause == nil && second.pause == nil)
        #expect(!route.isPaused)

        let third = await run(route)
        #expect(third.pause == .transport("no internet connection"))
        #expect(route.isPaused)
    }

    @Test func aSuccessResetsTheCount() async {
        let route = route(FakeNameSuggester([
            .failure(NamingError.rateLimited),
            .failure(NamingError.rateLimited),
            Self.reply(),
            .failure(NamingError.rateLimited),
            .failure(NamingError.rateLimited),
            .failure(NamingError.malformed),
        ]))

        for _ in 0..<5 { _ = await run(route) }
        #expect(!route.isPaused)

        #expect(await run(route).pause == .malformed)
    }

    @Test func manualScopeRunsWhilePaused() async {
        let client = FakeNameSuggester([.failure(NamingError.unauthorized), Self.reply()])
        let route = route(client)
        _ = await run(route)
        #expect(route.isPaused)

        let outcome = await run(route, .manual)

        #expect(client.requests.count == 2)
        #expect(outcome.actions.count == 1)
    }

    @Test func unusableReplyIsBilledAndCountsAsAFailure() async {
        let spent = NamingFailure(error: .truncated, usage: Self.usage)
        let route = route(FakeNameSuggester(Array(repeating: .failure(spent), count: 3)))

        let first = await run(route)
        #expect(first.failure == .truncated)
        #expect(first.usage == Self.usage)
        #expect(first.cost == Pricing.namingCost(Self.usage, overrides: [:]))
        #expect(first.actions.isEmpty)

        _ = await run(route)
        #expect(await run(route).pause == .truncated)
    }

    @Test func otherErrorsMapToTransport() async {
        let error = URLError(.cannotFindHost)
        let route = route(FakeNameSuggester([.failure(error)]))

        #expect(await run(route).failure == .transport(AnyError(error).description))
    }

    // MARK: - Logs

    /// R29: scope, counts, tokens, cost and duration; never a name, quote or transcript text.
    @Test func logsFiguresOnly() async throws {
        let sink = CapturingLogSink()
        let client = FakeNameSuggester([Self.reply(), .failure(NamingError.unauthorized)])
        let route = route(client, people: [(id: UUID(), name: "Priya Shah")])

        try await logging(to: sink) {
            client.hold()
            let flight = Task { await run(route) }
            await client.waitForRequests()
            clock.advance(by: 2.5)
            client.release()
            _ = await flight.value
            _ = await run(route)
        }

        #expect(!sink.records.isEmpty)
        #expect(sink.records.allSatisfy { $0.category == "naming" })
        for line in sink.lines {
            for secret in ["Kate", "Morgan", "I'm", "Welcome", "start", "Priya", "Niamh", "Neve"] {
                #expect(!line.contains(secret), "\(line) leaks \(secret)")
            }
        }
        let request = try #require(sink.lines.first { $0.contains("request") })
        #expect(request.contains("live"))
        #expect(request.contains("2 turns"))
        let rendered = NamingTranscript.render(segments: [introduction, answer])
        #expect(request.contains("\(rendered.blocks.joined().count) characters"))
        #expect(sink.lines.contains {
            $0.contains("live") && $0.contains("2.5 s") && $0.contains("1200 input") && $0.contains("300 cache-read")
                && $0.contains("40 cache-write") && $0.contains("90 output")
                && $0.contains(String(format: "%.6f", Pricing.namingCost(Self.usage, overrides: [:])))
        })
        #expect(sink.lines.contains { $0.contains("1 suggested") && $0.contains("0 applied") })
        #expect(sink.lines.contains { $0.contains("unauthorized") && $0.contains("paused") })
    }

    @Test func dropCountsAreLoggedByRule() async throws {
        let sink = CapturingLogSink()
        var unknown = Self.kate
        unknown.speaker = "S9"
        var nickname = Self.kate
        nickname.kind = "nickname"
        let route = route(FakeNameSuggester([Self.reply([unknown, unknown, nickname])]))

        try await logging(to: sink) { _ = await run(route) }

        #expect(sink.lines.contains { $0.contains("0 suggested") && $0.contains("rule 1: 2") && $0.contains("rule 2: 1") })
    }
}
