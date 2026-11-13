import Foundation
import Testing

import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWSupport
import MWTestCall
import MWTestSupport

private let sprintPlanning = TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")

/// A test meeting in the controller (design §5.3): the given engine and tag, the timing and
/// speech the conductor reads, segment arrivals, the Pause guard, the score at Stop and on open.
@MainActor
@Suite struct MeetingControllerTestCallTests {
    private static let record = TestCallRecord(
        scenario: .init(id: "sprint-planning", revision: 1, title: "Sprint planning"),
        engine: .speechmaticsStandard,
        overlap: false,
        scoredAt: MeetingHarness.wallStart,
        voices: [],
        lines: [.init(index: 1, role: .you, status: .done, reference: "Morning all.",
                      counts: .init(words: 2, substitutions: 0, deletions: 0, insertions: 0))],
        roles: [],
        overall: .init(words: 2, substitutions: 0, deletions: 0, insertions: 0),
        crossCredited: .init(voiceWordsAsYou: 0, yourWordsAsVoices: 0),
        latency: nil
    )
    private static let scenario = TestScenario(
        id: "sprint-planning", revision: 1, title: "Sprint planning",
        voices: [
            VoiceRole(role: .a, character: "Tom", requested: "Daniel"),
            VoiceRole(role: .b, character: "Priya", requested: "Karen"),
        ],
        lines: [
            ScenarioLine(role: .a, text: "Northwind ships the Kubernetes upgrade on Friday."),
            ScenarioLine(role: .you, text: "Agreed, Friday works for the rollout."),
        ]
    )
    /// What the engine heard: line 1 exactly, line 2 with one word substituted.
    private static let heard = ["Northwind ships the Kubernetes upgrade on Friday.", "Agreed, Friday works for a rollout."]

    /// Line 1 the voice from 0 s to 3 s, line 2 the user from 6 s to 9 s.
    private static func run(_ statuses: [TestCallLineStatus] = [.done, .done]) -> TestCallRun {
        TestCallRun(
            lines: [
                RunLine(index: 1, role: .a, status: statuses[0], start: 0, end: 3),
                RunLine(index: 2, role: .you, status: statuses[1], start: 6, end: 9),
            ],
            casting: [
                .a: CastVoice(role: .a, character: "Tom", requested: "Daniel", voice: "Daniel"),
                .b: CastVoice(role: .b, character: "Priya", requested: "Karen", voice: "Karen"),
            ],
            overlap: false
        )
    }

    // MARK: - Start

    @Test func givenEngineReplacesTheConfiguredOne() async throws {
        let assemblyAI = "placeholder-not-a-real-key-assemblyai"
        let harness = try await MeetingHarness(secrets: [.speechmatics: MeetingHarness.key, .assemblyai: assemblyAI]) {
            $0.meetingEngine = .speechmaticsStandard
        }

        try await harness.startTest(engine: .assemblyaiPro)

        #expect(harness.engines.calls.map(\.engine) == [.assemblyaiPro])
        #expect(harness.engines.calls.map(\.key) == [assemblyAI])
        #expect(harness.controller.meeting?.engine == .assemblyaiPro)
        #expect(try harness.stored().meeting.engine == .assemblyaiPro)
    }

    @Test func givenEngineWithoutItsKeyThrowsNoEngineKey() async throws {
        let harness = try await MeetingHarness(secrets: [.speechmatics: MeetingHarness.key])

        await #expect(throws: MeetingError.noEngineKey) { try await harness.startTest(engine: .assemblyaiStreaming) }

        #expect(harness.controller.state == .idle)
        #expect(harness.audio.calls.isEmpty)
        #expect(harness.engines.calls.isEmpty)
        #expect(try harness.store.index().isEmpty)
    }

    /// Start writes `meeting.json` once, at create, so the tag is there from the first byte.
    @Test func tagIsOnTheMeetingBeforeCreate() async throws {
        let harness = try await MeetingHarness()

        try await harness.startTest()

        #expect(harness.controller.meeting?.test == sprintPlanning)
        #expect(try harness.stored().meeting.test == sprintPlanning)
        #expect(try harness.store.index().map(\.test) == [sprintPlanning])
    }

    @Test func meetingTimeAndUserSpeechAreExposed() async throws {
        let harness = try await MeetingHarness()
        try await harness.startTest()

        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 2)
        #expect(harness.controller.meetingTime == 2)
        #expect(harness.controller.userSpeech == SpeechGate.View())

        harness.feed(MeetingHarness.loud(0.5))
        #expect(harness.controller.userSpeech.isSpeakingNow)
        #expect(harness.controller.userSpeech.spans.count == 1)
    }

    // MARK: - Pause

    @Test func pauseAndResumeDoNothingForATestMeeting() async throws {
        let harness = try await MeetingHarness()
        try await harness.startTest()
        harness.feed(MeetingHarness.loud(1))

        await harness.controller.pause()
        await harness.controller.resume()

        #expect(harness.controller.state == .recording)
        #expect(harness.controller.meeting?.markers.isEmpty == true)
        // The session stayed open and still streams.
        harness.feed(MeetingHarness.loud(1))
        #expect(harness.engines.engines.map(\.fedBuffers) == [20])
        #expect(harness.engines.engines.first?.finishTimeout == nil)
    }

    @Test func sleepStillPausesATestMeeting() async throws {
        let harness = try await MeetingHarness()
        try await harness.startTest()
        harness.feed(MeetingHarness.loud(1))

        harness.audio.sendMeeting(.systemWillSleep)

        await harness.waitFor(.state(.paused(.sleep)))
        await harness.waitFor(.marker(Marker(kind: .sleep, start: 1, end: 1)))
        // R12: Stop, not Resume, follows a sleep.
        await harness.controller.resume()
        #expect(harness.controller.state == .paused(.sleep))
        #expect(harness.engines.engines.count == 1)
    }

    // MARK: - Arrivals

    @Test func arrivalsAreRecordedAtAppendForTestMeetings() async throws {
        let harness = try await MeetingHarness()
        try await harness.startTest()
        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 3)

        try harness.sink(1).onSegment(TranscriptSegment(text: "Morning all.", speaker: "S1", start: 1, end: 2))

        let event = await harness.waitFor { if case .segmentAdded = $0 { true } else { false } }.last
        let segment = try #require(event.flatMap { if case .segmentAdded(let segment) = $0 { segment } else { nil } })
        #expect(harness.controller.segmentArrivals == [segment.id: 3])
    }

    @Test func ordinaryMeetingsRecordNoArrivals() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)

        try await harness.deliverSegment()

        #expect(harness.controller.segmentArrivals.isEmpty)
    }

    // MARK: - System audio

    /// The conductor's capture check needs every audible tick; the silence hint still settles
    /// once, on the first.
    @Test func lastAudibleSystemAudioUpdatesOnEveryAudibleTickAfterSettling() async throws {
        let harness = try await MeetingHarness()
        try await harness.startTest()
        harness.feed(MeetingHarness.loud(1))
        #expect(harness.controller.lastAudibleSystemAudio == nil)

        harness.pushSystem(MeetingHarness.loud(0.1))
        var events = await harness.tick(to: 1)
        #expect(harness.controller.lastAudibleSystemAudio == 1)

        harness.pushSystem(MeetingHarness.quiet(0.1))
        events += await harness.tick(to: 4)
        #expect(harness.controller.lastAudibleSystemAudio == 1)

        harness.pushSystem(MeetingHarness.loud(0.1))
        events += await harness.tick(to: 5)
        #expect(harness.controller.lastAudibleSystemAudio == 5)

        events += await harness.tick(to: 61)
        #expect(harness.controller.lastAudibleSystemAudio == 5)
        #expect(!events.contains(.systemAudio(.silentHint)))
    }

    // MARK: - Score at Stop

    @Test func finishTestWritesTheScoreSetsWERAndRefreshesTheIndex() async throws {
        let harness = try await MeetingHarness()
        try await recordTestCall(harness)

        await harness.controller.finishTest(Self.run(), scenario: Self.scenario)

        let record = try #require(Self.scored(await harness.waitFor(Self.isTestScore)))
        let id = try #require(harness.controller.meeting?.id)
        #expect(try harness.store.readTestCall(id) == record)
        #expect(record.overall == .init(words: 13, substitutions: 1, deletions: 0, insertions: 0))
        #expect(record.engine == .speechmaticsStandard)
        #expect(record.scoredAt == MeetingHarness.wallStart.addingTimeInterval(10))
        // Segments arrived at seconds 4 and 10, a second after each line ended.
        #expect(record.latency?.median == 1)
        let wer = try #require(record.overall.wer)
        #expect(harness.controller.meeting?.test?.wer == wer)
        #expect(try harness.stored().meeting.test?.wer == wer)
        #expect(try harness.store.index().map(\.test?.wer) == [wer])
    }

    /// R24: a test call bills at Stop and summarises like any meeting.
    @Test func stopStillBillsAndSummariseStillRuns() async throws {
        let harness = try await MeetingHarness(secrets: [.speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key])
        try await recordTestCall(harness)
        #expect(harness.usage.added.count == 1)

        await harness.controller.finishTest(Self.run(), scenario: Self.scenario)
        await harness.controller.summarise()

        #expect(harness.summarizer.calls.count == 1)
        let stored = try harness.stored().meeting
        #expect(stored.summary?.text == "## Summary\n\nShipped.")
        #expect(stored.test?.wer != nil)
        #expect(harness.usage.added.count == 2)
    }

    /// Design §5.6: the score still shows for this session; a later open cannot read it.
    @Test func writeFailureEmitsAnErrorAndStillTheScore() async throws {
        let harness = try await MeetingHarness()
        try await recordTestCall(harness)
        let id = try #require(harness.controller.meeting?.id)
        // The rename into place fails onto a directory.
        try FileManager.default.createDirectory(at: harness.testCallURL(id), withIntermediateDirectories: false)

        await harness.controller.finishTest(Self.run(), scenario: Self.scenario)

        let events = await harness.waitFor(Self.isTestScore)
        let errors = events.compactMap { if case .error(let message) = $0 { message } else { nil } }
        #expect(errors.count == 1)
        #expect(errors.first?.hasPrefix("Could not write the test score (") == true)
        let record = try #require(Self.scored(events))
        let wer = try #require(record.overall.wer)
        #expect(harness.controller.meeting?.test?.wer == wer)
        #expect(try harness.stored().meeting.test?.wer == wer)
        let reopened = try await scoresOnOpen(harness.stored()) { other, id in
            try FileManager.default.createDirectory(at: other.testCallURL(id), withIntermediateDirectories: false)
        }
        #expect(reopened == [.unreadable])
    }

    @Test func everyLineSkippedWritesAZeroLineRecordAndLeavesWERNil() async throws {
        let harness = try await MeetingHarness()
        try await recordTestCall(harness)

        await harness.controller.finishTest(Self.run([.skipped, .skipped]), scenario: Self.scenario)

        let record = try #require(Self.scored(await harness.waitFor(Self.isTestScore)))
        #expect(record.overall.words == 0)
        #expect(record.latency == nil)
        let id = try #require(harness.controller.meeting?.id)
        #expect(try harness.store.readTestCall(id) == record)
        #expect(try harness.stored().meeting.test == sprintPlanning)
    }

    @Test func finishTestOnAnOrdinaryMeetingDoesNothing() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        try await harness.deliverSegment()
        await harness.controller.stop(summarise: false)
        await harness.waitFor(.state(.stopped))

        await harness.controller.finishTest(Self.run(), scenario: Self.scenario)
        // Any later event shows whether a score came first.
        await harness.controller.rename(speaker: 0, to: "Sam")

        let events = await harness.waitFor { if case .speakers = $0 { true } else { false } }
        #expect(!events.contains(where: Self.isTestScore))
        let id = try #require(harness.controller.meeting?.id)
        #expect(try harness.store.readTestCall(id) == nil)
        #expect(try harness.stored().meeting.test == nil)
    }

    /// R27: ids, counts and times only.
    @Test func scoredLogLineCarriesNoText() async throws {
        let sink = CapturingLogSink()
        let harness = try await MeetingHarness()

        try await logging(to: sink) {
            try await recordTestCall(harness)
            await harness.controller.finishTest(Self.run(), scenario: Self.scenario)
        }

        #expect(sink.lines.filter { $0.contains("test call: scored") } == [
            "INFO meeting test call: scored wer=0.077 lines=2/2 latency_med=1.0",
        ])
        let words = Set((Self.scenario.lines.map(\.text) + Self.heard).flatMap {
            $0.lowercased().split { !$0.isLetter }.map(String.init)
        }.filter { $0.count >= 4 })
        for line in sink.lines.map({ $0.lowercased() }) {
            #expect(!words.contains { line.contains($0) }, "\(line)")
        }
    }

    /// Starts a test meeting on one second of audio, delivers each line's transcript a second
    /// after the line ends (meeting seconds 4 and 10), and stops without a summary.
    private func recordTestCall(_ harness: MeetingHarness) async throws {
        try await harness.startTest()
        harness.feed(MeetingHarness.quiet(1))
        for (text, start, arrival) in [(Self.heard[0], 0.5, 4.0), (Self.heard[1], 6.5, 10.0)] {
            await harness.clock.waitUntilSleeping()
            harness.clock.advance(by: arrival - harness.clock.now)
            try harness.sink(1).onSegment(TranscriptSegment(text: text, speaker: "S1", start: start, end: start + 2))
            await harness.waitFor { if case .segmentAdded = $0 { true } else { false } }
        }
        await harness.controller.stop(summarise: false)
    }

    private static func isTestScore(_ event: MeetingEvent) -> Bool {
        if case .testScore = event { true } else { false }
    }

    private static func scored(_ events: [MeetingEvent]) -> TestCallRecord? {
        events.lazy.compactMap { if case .testScore(.scored(let record)) = $0 { record } else { nil } }.last
    }

    // MARK: - Open

    @Test func openEmitsScored() async throws {
        var tag = sprintPlanning
        tag.wer = 0

        let scores = try await scoresOnOpen(MeetingFixtures.make(test: tag)) { harness, id in
            try await harness.store.writeTestCall(Self.record, of: id)
        }

        #expect(scores == [.scored(Self.record)])
    }

    @Test func openEmitsMissingWithoutFileOrWER() async throws {
        #expect(try await scoresOnOpen(MeetingFixtures.make(test: sprintPlanning)) == [.missing])
    }

    @Test func openEmitsUnreadableForAnUndecodableFileOrAWERWithoutFile() async throws {
        let garbled = try await scoresOnOpen(MeetingFixtures.make(test: sprintPlanning)) { harness, id in
            try Data("not json".utf8).write(to: harness.testCallURL(id))
        }
        var scored = sprintPlanning
        scored.wer = 0.064
        let lost = try await scoresOnOpen(MeetingFixtures.make(test: scored))

        #expect(garbled == [.unreadable])
        #expect(lost == [.unreadable])
    }

    @Test func openOfAnOrdinaryMeetingEmitsNoTestScore() async throws {
        #expect(try await scoresOnOpen(MeetingFixtures.northwind()).isEmpty)
    }

    /// The `.testScore` events of opening `loaded` in a fresh window, after `prepare` has run on
    /// the seeded store.
    private func scoresOnOpen(
        _ loaded: LoadedMeeting,
        _ prepare: (MeetingHarness, UUID) async throws -> Void = { _, _ in }
    ) async throws -> [TestScoreState] {
        let harness = try await MeetingHarness()
        let id = try await harness.seed(loaded)
        try await prepare(harness, id)
        try await harness.controller.open(id)
        return await harness.waitFor(.state(.stopped)).compactMap {
            if case .testScore(let score) = $0 { score } else { nil }
        }
    }
}

/// `Log.withSinks` around a main-actor body.
func logging(to sink: CapturingLogSink, _ body: @MainActor @Sendable () async throws -> Void) async throws {
    try await Log.withSinks(debug: true, sinks: [sink]) { try await body() }
}

private extension MeetingHarness {
    func startTest(engine: MeetingEngine? = nil, tag: TestCallTag = sprintPlanning) async throws {
        try await controller.start(mode: .remote, title: "Test call · Sprint planning", engine: engine, test: tag)
    }

    func testCallURL(_ id: UUID) -> URL {
        store.directory.appendingPathComponent(id.uuidString).appendingPathComponent("testcall.json")
    }

    /// Moves the clock to meeting second `second` and waits for the tick there.
    func tick(to second: Double) async -> [MeetingEvent] {
        await clock.waitUntilSleeping()
        clock.advance(by: second - clock.now)
        return await waitFor(.elapsed(second))
    }
}
