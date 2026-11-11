import Foundation
import Testing

import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWTestSupport

private let sprintPlanning = TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")

/// A test meeting in the controller (design §5.3): the given engine and tag, the timing and
/// speech the conductor reads, segment arrivals, the Pause guard and the score on open.
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
