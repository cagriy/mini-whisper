import Foundation
import Testing

import MWConfig
@testable import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWTestSupport

/// Rename, notes, speaker revisions, edits after Stop, open, retitle and summarise later
/// (design §5.6, §5.7).
@MainActor
@Suite struct MeetingControllerEditingTests {
    private static let alex = SpeakerLabel(id: 0, name: "Alex", isUser: true)
    private static let withAnthropic: [KeyAccount: String] = [
        .speechmatics: MeetingHarness.key, .anthropic: MeetingHarness.key,
    ]

    // MARK: - Speakers and notes

    @Test func renameUpdatesSpeakers() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        try await harness.deliverSegment()

        await harness.controller.rename(speaker: 1, to: " Marta ")

        let speakers = [Self.alex, SpeakerLabel(id: 1, name: "Marta", providerKeys: ["1:S1"])]
        await harness.waitFor(.speakers(speakers))
        #expect(try harness.stored().meeting.speakers == speakers)
    }

    @Test func renameToAnExistingNameMergesAndRewritesSegments() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        try harness.sink(1).onSegment(TranscriptSegment(text: "First.", speaker: "S1", start: 0, end: 1))
        try harness.sink(1).onSegment(TranscriptSegment(text: "Second.", speaker: "S2", start: 1, end: 2))
        await harness.waitFor { if case .segmentAdded(let segment) = $0 { segment.speaker == 2 } else { false } }
        await harness.controller.rename(speaker: 1, to: "Marta")

        await harness.controller.rename(speaker: 2, to: "Marta")

        let merged = [Self.alex, SpeakerLabel(id: 1, name: "Marta", providerKeys: ["1:S1", "1:S2"])]
        let events = await harness.waitFor(.speakers(merged))
        let updated = events.compactMap { if case .segmentUpdated(let segment) = $0 { segment } else { nil } }
        #expect(updated.map(\.text) == ["Second."])
        #expect(updated.map(\.speaker) == [1])
        let stored = try harness.stored()
        #expect(stored.segments.map(\.speaker) == [1, 1])
        #expect(stored.meeting.speakers == merged)
    }

    @Test func addNotePersistsAndEmitsAtTheFirstKeystrokeTime() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 12)

        await harness.controller.addNote("  Ask legal about the cap  ", firstKeystrokeAt: 9.5)

        let event = await harness.waitFor { if case .note = $0 { true } else { false } }.last
        let note = try #require(event.flatMap { if case .note(let note) = $0 { note } else { nil } })
        #expect(note.time == 9.5)
        #expect(note.text == "Ask legal about the cap")
        #expect(note.createdAt == MeetingHarness.wallStart.addingTimeInterval(12))
        #expect(try harness.stored().notes == [note])
    }

    // MARK: - Revisions

    @Test func speakerRevisionRemapsByTurnOrderWithinItsSession() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        let first = try harness.sink(1)
        first.onSegment(TranscriptSegment(text: "Turn zero.", speaker: "A", turnOrder: 0, start: 0, end: 1))
        first.onSegment(TranscriptSegment(text: "Turn one.", speaker: "B", turnOrder: 1, start: 1, end: 2))
        // A Speechmatics warning rolls over at once; session 2 has a turn 1 of its own.
        first.onSessionLimit(.warning)
        try harness.sink(2).onSegment(TranscriptSegment(text: "Other turn one.", speaker: "B", turnOrder: 1, start: 0, end: 1))
        await harness.waitFor { if case .segmentAdded(let segment) = $0 { segment.session == 2 } else { false } }

        first.onSpeakerRevision([SpeakerRevision(turnOrder: 1, speaker: "A")])

        let event = await harness.waitFor { if case .segmentUpdated = $0 { true } else { false } }.last
        let revised = try #require(event.flatMap { if case .segmentUpdated(let segment) = $0 { segment } else { nil } })
        #expect(revised.text == "Turn one.")
        #expect(revised.speaker == 1)
        #expect(revised.providerLabel == "A")
        let stored = try harness.stored().segments
        #expect(stored.map(\.speaker) == [1, 1, 3])
        #expect(stored.map(\.providerLabel) == ["A", "A", "B"])
    }

    @Test func pinnedSegmentIsNeverRevised() {
        var registry = SpeakerRegistry(userName: "Alex")
        let a = registry.resolve(session: 1, label: "A")
        let b = registry.resolve(session: 1, label: "B")
        var segments = [
            Segment(speaker: a, start: 0, end: 1, text: "Pinned.", session: 1, providerLabel: "A", turnOrder: 4, pinned: true),
            Segment(speaker: a, start: 1, end: 2, text: "Free.", session: 1, providerLabel: "A", turnOrder: 4),
        ]
        let pinned = segments[0]

        let changed = MeetingController.revise(
            &segments, with: [SpeakerRevision(turnOrder: 4, speaker: "B")], session: 1, registry: &registry
        )

        #expect(changed == [1])
        #expect(segments[0] == pinned)
        #expect(segments[1].speaker == b)
    }

    // MARK: - Edits after Stop

    @Test func editIsRefusedWhileRecording() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        try await harness.deliverSegment()
        let segment = try #require(try harness.stored().segments.first)

        await harness.controller.edit(segment: segment.id, text: "We ship on Monday.")
        await harness.controller.reassign(segment: segment.id, to: 0)
        await harness.controller.stop(summarise: false)

        let events = await harness.waitFor(.state(.stopped))
        #expect(!events.contains { if case .segmentUpdated = $0 { true } else { false } })
        #expect(try harness.stored().segments == [segment])
    }

    @Test func editAfterStopPersistsAndMarksEdited() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        try await harness.deliverSegment()
        await harness.controller.stop(summarise: false)
        let segment = try #require(try harness.stored().segments.first)

        await harness.controller.edit(segment: segment.id, text: "We ship on Monday.")

        var expected = segment
        expected.text = "We ship on Monday."
        expected.edited = true
        await harness.waitFor(.segmentUpdated(expected))
        #expect(try harness.stored().segments == [expected])
    }

    @Test func reassignAfterStopPinsAndPersists() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        try await harness.deliverSegment()
        await harness.controller.stop(summarise: false)
        let segment = try #require(try harness.stored().segments.first)

        await harness.controller.reassign(segment: segment.id, to: 0)
        await harness.controller.reassign(segment: segment.id, to: 7)

        var expected = segment
        expected.speaker = 0
        expected.pinned = true
        await harness.waitFor(.segmentUpdated(expected))
        #expect(try harness.stored().segments == [expected])
    }

    // MARK: - Stored meetings

    @Test func openLoadsAStoredMeetingIntoStopped() async throws {
        let harness = try await MeetingHarness()
        let id = try await harness.seed(MeetingFixtures.northwind())
        let stored = try harness.store.load(id)

        try await harness.controller.open(id)

        let events = await harness.waitFor(.state(.stopped))
        #expect(harness.controller.state == .stopped)
        #expect(harness.controller.meeting == stored.meeting)
        #expect(events.contains(.speakers(stored.meeting.speakers)))
        #expect(events.compactMap { if case .marker(let marker) = $0 { marker } else { nil } } == stored.meeting.markers)
        #expect(events.compactMap { if case .segmentAdded(let segment) = $0 { segment } else { nil } } == stored.segments)
        #expect(events.compactMap { if case .note(let note) = $0 { note } else { nil } } == stored.notes)
        #expect(events.contains(.summary(.ready(try #require(stored.meeting.summary)))))
        #expect(harness.audio.calls.isEmpty)
        #expect(harness.engines.calls.isEmpty)
    }

    @Test func retitleRewritesMeetingJSON() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)

        await harness.controller.retitle(" Northwind sync ")

        #expect(harness.controller.meeting?.title == "Northwind sync")
        #expect(try harness.stored().meeting.title == "Northwind sync")
        #expect(try harness.store.index().map(\.title) == ["Northwind sync"])
    }

    @Test func summariseLaterWorksOnAnOpenedMeetingWithoutASummary() async throws {
        let harness = try await MeetingHarness(secrets: Self.withAnthropic)
        var northwind = MeetingFixtures.northwind()
        northwind.meeting.summary = nil
        let id = try await harness.seed(northwind)
        try await harness.controller.open(id)

        await harness.controller.summarise()

        let event = await harness.waitFor { if case .summary(.ready) = $0 { true } else { false } }.last
        let summary = try #require(event.flatMap { if case .summary(.ready(let summary)) = $0 { summary } else { nil } })
        #expect(summary.text == "## Summary\n\nShipped.")
        #expect(harness.summarizer.calls.count == 1)
        #expect(try harness.stored().meeting.summary == summary)
    }

    @Test func summariseIsANoOpWhenASummaryExists() async throws {
        let harness = try await MeetingHarness(secrets: Self.withAnthropic)
        let id = try await harness.seed(MeetingFixtures.northwind())
        try await harness.controller.open(id)
        let stored = try harness.stored()

        await harness.controller.summarise()

        #expect(harness.summarizer.calls.isEmpty)
        #expect(try harness.stored() == stored)
    }
}

extension MeetingHarness {
    /// Writes a meeting to the store as a past recording left it.
    func seed(_ loaded: LoadedMeeting) async throws -> UUID {
        let id = loaded.meeting.id
        try await store.create(loaded.meeting)
        for segment in loaded.segments { try await store.append(segment, to: id) }
        for note in loaded.notes { try await store.append(note, to: id) }
        return id
    }
}
