import MWMeetings
import MWSupport

/// Drives a test-call script on an injected clock (design §5.3 Conductor contract, §5.5).
///
/// Each line ends before the next starts, except an overlap: there the voice line after the
/// user's starts 1.5 s into their speech, and the script moves on once both have ended. The
/// conductor polls every 100 ms while `say` plays in its own task, so Skip, Stop and the overlap
/// launch take effect within one poll.
@MainActor
public final class TestCallConductor {
    static let handOverPause = 1.2
    static let silenceSkip = 20.0
    static let userLineCap = 30.0
    static let overlapDelay = 1.5
    static let poll = Duration.milliseconds(100)
    /// Meeting times are sums of floating seconds; a deadline met to within this counts as met.
    private static let tolerance = 1e-6

    public nonisolated let events: AsyncStream<ConductorEvent>
    public private(set) var result: TestCallRun

    private nonisolated let continuation: AsyncStream<ConductorEvent>.Continuation
    private let scenario: TestScenario
    private let player: any SpeechPlaying
    private let sensor: any UserSpeechSensing
    private let clock: any Clock
    private let log = Log.meeting

    private var started = false
    private var ending: EndReason?
    /// Array indices of the lines under way: one, or a user line and the voice overlapping it.
    private var running: Set<Int> = []
    /// The voice line whose `play` has not returned.
    private var playing: Int?
    /// The user line under way, picked for overlap, whose voice has not launched yet.
    private var pendingOverlap: Int?
    /// `say` runs that failed since the last one that exited normally.
    private var failures = 0

    public init(
        scenario: TestScenario,
        casting: [TestCallRole: CastVoice],
        overlap: Bool,
        player: any SpeechPlaying,
        sensor: any UserSpeechSensing,
        clock: any Clock,
        rng: inout some RandomNumberGenerator
    ) {
        self.scenario = scenario
        self.player = player
        self.sensor = sensor
        self.clock = clock
        var lines = scenario.lines.enumerated().map { RunLine(index: $0.offset + 1, role: $0.element.role) }
        if overlap {
            let candidates = lines.indices.dropLast().filter { lines[$0].role == .you && lines[$0 + 1].role != .you }
            for index in candidates.shuffled(using: &rng).prefix((candidates.count + 2) / 3) {
                lines[index].overlapped = true
                lines[index + 1].overlapped = true
            }
        }
        result = TestCallRun(lines: lines, casting: casting, overlap: overlap)
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        continuation.finish()
    }

    /// Plays the script once. Returns after `.finished`, or after `end(_:)` once `say` has exited.
    public func run() async {
        guard !started, ending == nil else { return }
        started = true
        for role in [TestCallRole.a, .b] {
            if let cast = result.casting[role], cast.voice != cast.requested {
                log.info("test call: voice substituted \(cast.requested)->\(cast.voice)")
            }
        }
        var index = 0
        while index < scenario.lines.count, ending == nil, failures < 2 {
            let next = await (scenario.lines[index].role == .you ? userTurn(index) : voiceTurn(index))
            guard let next else { return }
            index = next
        }
        guard ending == nil else { return }
        if failures >= 2 { emit(.voicesFailed) }
        emit(.finished)
        continuation.finish()
    }

    /// Ends every line under way at once; skipped lines are left out of the score.
    public func skip() {
        for index in running.sorted() { markSkipped(index, .skipped) }
        if playing != nil { player.stop() }
    }

    /// Stop or sleep: the lines under way become `stopped` and the rest stay `notReached`.
    public func end(_ reason: EndReason) {
        guard ending == nil else { return }
        ending = reason
        dropPendingOverlap()
        for index in running { result.lines[index].status = .stopped }
        running.removeAll()
        if playing != nil { player.stop() }
        continuation.finish()
    }

    // MARK: - Turns

    /// Returns the next line's array index, or nil once the task is cancelled.
    private func voiceTurn(_ index: Int) async -> Int? {
        launch(index)
        while playing != nil {
            guard await tick() else { return nil }
        }
        return index + 1
    }

    /// The user's line, plus the voice line after it when that one overlaps. Returns the next
    /// line's array index, or nil once the task is cancelled.
    private func userTurn(_ index: Int) async -> Int? {
        let prompt = sensor.meetingTime
        running.insert(index)
        pendingOverlap = result.lines[index].overlapped ? index : nil
        emit(.line(index + 1, .yourTurn))
        var next = index + 1
        while true {
            if running.contains(index) { follow(index, since: prompt) }
            if pendingOverlap != nil {
                if !running.contains(index) {
                    dropPendingOverlap()
                } else if let onset = result.lines[index].start, reached(onset + Self.overlapDelay) {
                    pendingOverlap = nil
                    launch(index + 1)
                    next = index + 2
                }
            }
            if running.isEmpty, playing == nil { return next }
            guard await tick() else { return nil }
        }
    }

    /// Ends the user's line at the hand-over, the 30 s cap or 20 s of silence.
    private func follow(_ index: Int, since prompt: Double) {
        let spans = sensor.speechSpans.drop { $0.lowerBound < prompt }
        guard let first = spans.first, let last = spans.last else {
            if reached(prompt + Self.silenceSkip) { markSkipped(index, .noSpeech) }
            return
        }
        result.lines[index].start = first.lowerBound
        let paused = !sensor.isSpeaking && reached(last.upperBound + Self.handOverPause)
        guard paused || reached(first.lowerBound + Self.userLineCap) else { return }
        result.lines[index].end = last.upperBound
        result.lines[index].status = .done
        running.remove(index)
    }

    // MARK: - Voices

    private func launch(_ index: Int) {
        let line = scenario.lines[index]
        running.insert(index)
        playing = index
        emit(.line(index + 1, .voiceSpeaking(line.role)))
        Task {
            // A Skip or Stop can land before this task runs; a role without a voice cannot play.
            guard let voice = result.casting[line.role]?.voice, running.contains(index) else {
                let now = sensor.meetingTime
                return finishVoice(index, Playback(launched: now, exited: now, normalExit: false))
            }
            finishVoice(index, await player.play(VoiceLine(text: line.text, voice: voice)))
        }
    }

    private func finishVoice(_ index: Int, _ playback: Playback) {
        if playing == index { playing = nil }
        result.lines[index].start = playback.launched
        result.lines[index].end = playback.exited
        // Skip and `end(_:)` settle a line before its `say` has exited.
        guard running.remove(index) != nil else { return }
        guard playback.normalExit else {
            failures += 1
            return markSkipped(index, .voiceFailed)
        }
        failures = 0
        result.lines[index].status = .done
        if (sensor.lastAudibleSystemAudio ?? -.infinity) < playback.launched {
            emit(.captureMissing(index + 1))
        }
    }

    // MARK: - Helpers

    private func markSkipped(_ index: Int, _ reason: SkipReason) {
        running.remove(index)
        result.lines[index].status = .skipped
        result.lines[index].skipReason = reason
        emit(.skipped(index + 1, reason))
        log.info("test call: line \(index + 1) skipped (\(reason.rawValue))")
    }

    /// The user's line ended before its overlapping voice launched, so neither line overlapped.
    private func dropPendingOverlap() {
        guard let index = pendingOverlap else { return }
        pendingOverlap = nil
        result.lines[index].overlapped = false
        result.lines[index + 1].overlapped = false
    }

    private func reached(_ deadline: Double) -> Bool {
        sensor.meetingTime >= deadline - Self.tolerance
    }

    /// Sleeps one poll. Cancelling the task that runs the script stops it.
    private func tick() async -> Bool {
        do {
            try await clock.sleep(for: Self.poll)
            return true
        } catch {
            end(.stop)
            return false
        }
    }

    private func emit(_ event: ConductorEvent) {
        continuation.yield(event)
    }
}
