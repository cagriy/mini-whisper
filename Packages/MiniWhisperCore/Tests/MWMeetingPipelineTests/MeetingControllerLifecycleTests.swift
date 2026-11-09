import Foundation
import Testing

import MWAudio
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWTestSupport

/// Pause, sleep, device changes, the silence hint, `isActive` and the write-error fallback
/// (design §5.6, §5.7).
@MainActor
@Suite struct MeetingControllerLifecycleTests {
    // MARK: - Pause and sleep

    @Test func pauseClosesTheSessionAndOpensAPausedMarker() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        harness.feed(MeetingHarness.loud(1))

        await harness.controller.pause()

        let opened = Marker(kind: .paused, start: 1, end: 1)
        let events = await harness.waitFor(.marker(opened))
        #expect(events.contains(.state(.paused(.user))))
        #expect(harness.engines.engines.first?.finishTimeout == .seconds(5))
        #expect(harness.tap?.stopCount == 0)
        #expect(try harness.stored().meeting.markers == [opened])
        let written = harness.writers.last?.events.count
        harness.feed(MeetingHarness.loud(1))
        #expect(harness.engines.engines.map(\.fedBuffers) == [10])
        #expect(harness.writers.last?.events.count == written)
    }

    @Test func resumePadsSilenceClosesTheMarkerAndOpensANewSession() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        harness.feed(MeetingHarness.loud(1))
        await harness.controller.pause()
        harness.feed(MeetingHarness.loud(2))

        await harness.controller.resume()

        let closed = Marker(kind: .paused, start: 1, end: 3)
        await harness.waitFor(.marker(closed))
        await harness.waitFor(.state(.recording))
        #expect(harness.writers.last?.events.last == .silence(seconds: 2))
        #expect(harness.engines.engines.count == 2)
        harness.feed(MeetingHarness.loud(0.1))
        #expect(harness.engines.engines.map(\.fedBuffers) == [10, 1])
        #expect(try harness.stored().meeting.markers == [closed])
    }

    @Test func sleepAutoPausesWithTheSleepReasonAndStaysPaused() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        harness.feed(MeetingHarness.loud(1))

        harness.audio.sendMeeting(.systemWillSleep)

        await harness.waitFor(.state(.paused(.sleep)))
        await harness.waitFor(.marker(Marker(kind: .sleep, start: 1, end: 1)))
        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 30)
        await harness.waitFor(.elapsed(30))
        #expect(harness.controller.state == .paused(.sleep))
        #expect(harness.engines.engines.count == 1)

        // No buffers arrived while asleep: the file and the marker still cover the whole span.
        await harness.controller.resume()
        await harness.waitFor(.marker(Marker(kind: .sleep, start: 1, end: 30)))
        #expect(harness.writers.last?.events.last == .silence(seconds: 29))
    }

    @Test func stopWhilePausedClosesThePauseMarker() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        harness.feed(MeetingHarness.loud(1))
        await harness.controller.pause()
        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 5)

        await harness.controller.stop(summarise: false)

        #expect(try harness.stored().meeting.markers == [Marker(kind: .paused, start: 1, end: 5)])
        #expect(harness.writers.last?.events.last == .finish)
    }

    // MARK: - Device changes

    @Test func deviceChangeRestartsCaptureAndReappliesVoiceProcessing() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        let calls = harness.audio.calls.count

        harness.audio.sendMeeting(.deviceChanged)
        // Handled in order, so the sleep pause marks the end of the device change.
        harness.audio.sendMeeting(.systemWillSleep)
        await harness.waitFor(.state(.paused(.sleep)))

        #expect(Array(harness.audio.calls.dropFirst(calls)) == [.ensureRunning, .setVoiceProcessing(true)])
    }

    @Test func deviceChangeLosingMoreThanTwoSecondsWritesAGap() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        harness.feed(MeetingHarness.loud(1))
        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 4)

        harness.audio.sendMeeting(.deviceChanged)

        let gap = Marker(kind: .gap, start: 1, end: 4, reason: "input device changed")
        await harness.waitFor(.marker(gap))
        #expect(harness.writers.last?.events.last == .silence(seconds: 3))
        // Session 1 heard nothing for those 3 s, so its later words land after the gap.
        try harness.sink(1).onSegment(TranscriptSegment(text: "We're back.", speaker: "S1", start: 1.5, end: 2))
        let added = await harness.waitFor { if case .segmentAdded = $0 { true } else { false } }.last
        let segment = try #require(added.flatMap { if case .segmentAdded(let s) = $0 { s } else { nil } })
        #expect(segment.start == 4.5)
        #expect(segment.end == 5)
        await harness.controller.stop(summarise: false)
        #expect(try harness.stored().meeting.markers == [gap])
    }

    @Test func deviceChangeUnderTwoSecondsWritesNoGap() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        harness.feed(MeetingHarness.loud(1))
        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 3)

        harness.audio.sendMeeting(.deviceChanged)
        harness.audio.sendMeeting(.systemWillSleep)

        let events = await harness.waitFor(.state(.paused(.sleep)))
        #expect(!events.contains { if case .marker(let marker) = $0 { marker.kind == .gap } else { false } })
        #expect(harness.writers.last?.events.last == .silence(seconds: 2))
    }

    @Test func defaultOutputChangeFollowsTheSameTwoSecondRule() async throws {
        let short = try await MeetingHarness()
        try await short.start(.remote)
        short.pushSystem(MeetingHarness.quiet(0.1))
        await short.clock.waitUntilSleeping()
        short.clock.advance(by: 2)

        short.tap?.send(.defaultOutputChanged)
        short.tap?.send(.stopped(StubError(errorDescription: "device gone")))

        let events = await short.waitFor(.systemAudio(.unavailable("device gone")))
        #expect(!events.contains { if case .marker = $0 { true } else { false } })

        let long = try await MeetingHarness()
        try await long.start(.remote)
        long.pushSystem(MeetingHarness.quiet(0.1))
        await long.clock.waitUntilSleeping()
        long.clock.advance(by: 3)

        long.tap?.send(.defaultOutputChanged)

        await long.waitFor(.marker(Marker(kind: .gap, start: 0, end: 3, reason: "output device changed")))
    }

    // MARK: - Silence hint

    @Test func silenceHintAfterSixtySecondsOfOneSidedSpeech() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        harness.feed(MeetingHarness.loud(1))
        harness.pushSystem(MeetingHarness.quiet(1))

        var events: [MeetingEvent] = []
        for second in [59.0, 60, 61] {
            await harness.clock.waitUntilSleeping()
            harness.clock.advance(by: second - harness.clock.now)
            events += await harness.waitFor(.elapsed(second))
        }

        #expect(events.filter { $0 == .systemAudio(.silentHint) }.count == 1)
        let hint = try #require(events.firstIndex(of: .systemAudio(.silentHint)))
        #expect(try hint > #require(events.firstIndex(of: .elapsed(59))))
        #expect(try hint < #require(events.firstIndex(of: .elapsed(60))))
    }

    @Test func noSilenceHintWhenSystemAudioArrives() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.remote)
        harness.feed(MeetingHarness.loud(1))
        harness.pushSystem(MeetingHarness.loud(0.1))

        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 60)

        let events = await harness.waitFor(.elapsed(60))
        #expect(!events.contains(.systemAudio(.silentHint)))
    }

    // MARK: - isActive

    @Test func isActiveWhileStartingRecordingPausedAndStopping() async throws {
        let harness = try await MeetingHarness()
        #expect(!harness.controller.isActive)

        try await harness.start(.inRoom)
        #expect(harness.controller.isActive)
        await harness.controller.pause()
        #expect(harness.controller.isActive)
        await harness.controller.stop(summarise: false)
        #expect(!harness.controller.isActive)

        let states = await harness.waitFor(.state(.stopped)).compactMap { event -> MeetingState? in
            if case .state(let state) = event { state } else { nil }
        }
        #expect(states == [.starting, .recording, .paused(.user), .stopping, .stopped])
        #expect(states.map(\.isActive) == [true, true, true, true, false])
        #expect(MeetingState.paused(.sleep).isActive)
        #expect(!MeetingState.idle.isActive)
    }

    // MARK: - Write errors

    @Test func appendFailureEmitsAnErrorKeepsSegmentsInMemoryAndRetries() async throws {
        let harness = try await MeetingHarness()
        try await harness.start(.inRoom)
        let id = try #require(harness.controller.meeting?.id)
        let file = harness.store.directory.appendingPathComponent(id.uuidString).appendingPathComponent("segments.jsonl")
        let manager = FileManager.default
        try manager.setAttributes([.posixPermissions: 0o400], ofItemAtPath: file.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        // Run as root the file stays writable and the test would pass vacuously.
        try #require(!manager.isWritableFile(atPath: file.path))

        var events: [MeetingEvent] = []
        for (index, text) in ["One.", "Two."].enumerated() {
            try harness.sink(1).onSegment(TranscriptSegment(text: text, start: Double(index), end: Double(index + 1)))
            events += await harness.waitFor { if case .segmentAdded = $0 { true } else { false } }
        }

        let errors = events.compactMap { if case .error(let message) = $0 { message } else { nil } }
        #expect(errors.count == 1)
        #expect(errors.first?.hasPrefix("Could not write the transcript (") == true)
        #expect(errors.first?.hasSuffix("); recording continues in memory") == true)
        #expect(try harness.stored().segments.isEmpty)

        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try harness.sink(1).onSegment(TranscriptSegment(text: "Three.", start: 2, end: 3))
        await harness.waitFor { if case .segmentAdded = $0 { true } else { false } }
        #expect(try harness.stored().segments.map(\.text) == ["One.", "Two.", "Three."])
    }
}
