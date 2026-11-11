import Foundation
import Testing

import MWMeetings
import MWOverlaySim
import MWSupport
import MWTestCall
import MWTestSupport

/// Meeting seconds at clock zero, so a conductor reading the clock instead of the sensor is off.
private let origin = 100.0

private let texts = [
    "Morning both, the release review starts at half past ten.",
    "I looked at those failures yesterday; the retry header is wrong.",
    "Then the remaining risk is the Kubernetes upgrade.",
    "Let's ask operations for Wednesday night.",
    "I'll send them the runbook today and copy you both.",
    "Good, that settles the sprint.",
]

private let sixLines: [TestCallRole] = [.a, .you, .b, .a, .you, .b]

private let casting: [TestCallRole: CastVoice] = [
    .a: CastVoice(role: .a, character: "Tom", requested: "Daniel", voice: "Daniel"),
    .b: CastVoice(role: .b, character: "Priya", requested: "Karen", voice: "Moira"),
]

/// Design §5.3 Conductor contract and the §5.11 conductor row, on `VirtualClock`.
@MainActor
@Suite
struct TestCallConductorTests {
    // MARK: - Voice lines

    @Test func voiceLinesPlayInOrderAndTheNextStartsOnExit() async {
        let rig = Rig([.a, .b])
        rig.start()

        await rig.player.waitUntilPlaying(1)
        #expect(rig.player.lines == [VoiceLine(text: texts[0], voice: "Daniel")])
        await rig.step(2.5)
        #expect(rig.player.lines.count == 1)

        rig.player.finish()
        await rig.step()
        await rig.player.waitUntilPlaying(2)
        #expect(rig.player.lines.last == VoiceLine(text: texts[1], voice: "Moira"))
        await rig.step(4)
        rig.player.finish()
        await rig.advance()
        await rig.done()

        #expect(rig.lines.map(\.status) == [.done, .done])
        #expect(rig.lines.map(\.start) == rig.player.playbacks.map(\.launched))
        #expect(rig.lines.map(\.end) == rig.player.playbacks.map(\.exited))
        #expect(await rig.events() == [.line(1, .voiceSpeaking(.a)), .line(2, .voiceSpeaking(.b)), .finished])
    }

    // MARK: - The user's lines

    @Test func userLineHandsOverExactly1Point2SecondsAfterTheSpanEnd() async {
        let rig = Rig()
        // Speech during the voice line, before the prompt, does not start the user's line.
        rig.sensor.spans = [origin + 1 ... origin + 2]
        rig.start()
        await rig.voice(1)

        await rig.step(0.5)
        let onset = rig.now
        rig.sensor.startSpeaking()
        await rig.step(2.5)
        let spanEnd = rig.now
        rig.sensor.stopSpeaking()

        await rig.step(1.1)
        #expect(rig.lines[1].status == .notReached)
        #expect(rig.player.lines.count == 1)

        await rig.step(0.1)
        await rig.player.waitUntilPlaying(2)
        #expect(rig.lines[1].status == .done)
        #expect(rig.lines[1].start == onset)
        #expect(rig.lines[1].end == spanEnd)
        await rig.stop()
    }

    @Test func noHandOverWhileTheUserIsStillSpeaking() async {
        let rig = Rig()
        rig.start()
        await rig.voice(1)
        rig.sensor.startSpeaking()
        await rig.step(2)
        rig.sensor.stopSpeaking()
        rig.sensor.isSpeaking = true

        await rig.step(1.2)
        #expect(rig.lines[1].status == .notReached)

        rig.sensor.isSpeaking = false
        await rig.step()
        await rig.player.waitUntilPlaying(2)
        #expect(rig.lines[1].status == .done)
        await rig.stop()
    }

    @Test func twentySecondsWithoutSpeechSkipsTheLine() async {
        let rig = Rig()
        rig.start()
        await rig.voice(1)

        await rig.step(19.9)
        #expect(rig.lines[1].status == .notReached)
        await rig.step(0.1)
        await rig.player.waitUntilPlaying(2)

        #expect(rig.lines[1].status == .skipped)
        #expect(rig.lines[1].skipReason == .noSpeech)
        #expect(rig.lines[1].start == nil)
        await rig.stop()
        #expect(await rig.events().contains(.skipped(2, .noSpeech)))
    }

    @Test func thirtySecondsOfSpeechHandsOverAndScores() async {
        let rig = Rig()
        rig.start()
        await rig.voice(1)
        await rig.step(1)
        let onset = rig.now
        rig.sensor.startSpeaking()

        await rig.step(29.9)
        #expect(rig.lines[1].status == .notReached)
        await rig.step(0.1)
        await rig.player.waitUntilPlaying(2)

        #expect(rig.lines[1].status == .done)
        #expect(rig.lines[1].start == onset)
        // The open span runs up to the hand-over.
        #expect(rig.lines[1].end == rig.now)
        await rig.stop()
    }

    // MARK: - Skip

    @Test func skipDuringAVoiceStopsThePlayer() async {
        let rig = Rig()
        rig.start()
        await rig.player.waitUntilPlaying(1)
        await rig.step(1)

        rig.conductor.skip()

        #expect(rig.player.stops == 1)
        #expect(rig.lines[0].status == .skipped)
        #expect(rig.lines[0].skipReason == .skipped)
        // The stopped `say` is no failure: one real failure after it only skips its line.
        await rig.step()
        rig.conductor.skip()
        await rig.step()
        await rig.player.waitUntilPlaying(2)
        rig.player.fail()
        await rig.step()
        await rig.player.waitUntilPlaying(3)
        #expect(rig.lines[2].skipReason == .voiceFailed)
        await rig.stop()
        #expect(!(await rig.events()).contains(.voicesFailed))
    }

    @Test func skipDuringTheUsersTurn() async {
        let rig = Rig()
        rig.start()
        await rig.voice(1)
        await rig.step(0.5)
        rig.sensor.startSpeaking()
        await rig.step(2)

        rig.conductor.skip()

        #expect(rig.lines[1].status == .skipped)
        #expect(rig.lines[1].skipReason == .skipped)
        await rig.step()
        await rig.player.waitUntilPlaying(2)
        #expect(rig.player.stops == 0)
        await rig.stop()
        #expect(await rig.events() == [
            .line(1, .voiceSpeaking(.a)), .line(2, .yourTurn), .skipped(2, .skipped), .line(3, .voiceSpeaking(.b)),
        ])
    }

    // MARK: - Overlap

    @Test func overlapStartsTheVoiceAt1Point5SecondsAfterOnset() async {
        let rig = Rig([.a, .you, .b, .a], overlap: true)
        #expect(rig.lines.map(\.overlapped) == [false, true, true, false])
        rig.start()
        await rig.voice(1)
        await rig.step(0.4)
        let onset = rig.now
        rig.sensor.startSpeaking()

        await rig.step(1.4)
        #expect(rig.player.lines.count == 1)
        await rig.step(0.1)
        await rig.player.waitUntilPlaying(2)
        #expect(rig.player.lines.last?.text == texts[2])
        #expect(abs(rig.player.launches[1] - (onset + 1.5)) < 1e-9)

        // The user hands over while the voice still speaks: the script waits for `say`.
        await rig.step(1)
        rig.sensor.stopSpeaking()
        await rig.step(1.2)
        #expect(rig.lines[1].status == .done)
        #expect(rig.player.lines.count == 2)

        await rig.step(1)
        rig.player.finish()
        await rig.step()
        await rig.player.waitUntilPlaying(3)
        #expect(rig.lines[2].status == .done)
        #expect(rig.lines[2].start == rig.player.playbacks[1].launched)
        #expect(rig.lines.map(\.overlapped) == [false, true, true, false])
        await rig.stop()
        #expect(await rig.events() == [
            .line(1, .voiceSpeaking(.a)), .line(2, .yourTurn), .line(3, .voiceSpeaking(.b)),
            .line(4, .voiceSpeaking(.a)),
        ])
    }

    @Test func overlapWaitsForTheHandOverWhenTheVoiceEndsFirst() async {
        let rig = Rig([.a, .you, .b, .a], overlap: true)
        rig.start()
        await rig.voice(1)
        rig.sensor.startSpeaking()
        await rig.step(1.5)
        await rig.player.waitUntilPlaying(2)
        await rig.step(2)
        rig.player.finish()

        await rig.step(3)
        #expect(rig.lines[2].status == .done)
        #expect(rig.lines[1].status == .notReached)
        #expect(rig.player.lines.count == 2)

        rig.sensor.stopSpeaking()
        await rig.step(1.2)
        await rig.player.waitUntilPlaying(3)
        #expect(rig.lines[1].status == .done)
        await rig.stop()
    }

    @Test func anOverlapThatNeverStartsIsNotRecorded() async {
        let rig = Rig([.a, .you, .b, .a], overlap: true)
        rig.start()
        await rig.voice(1)

        await rig.step(20)
        await rig.player.waitUntilPlaying(2)

        #expect(rig.lines[1].skipReason == .noSpeech)
        #expect(rig.lines.map(\.overlapped) == [false, false, false, false])
        await rig.stop()
    }

    @Test func skipDuringAnOverlapEndsBothLines() async {
        let rig = Rig([.a, .you, .b, .a], overlap: true)
        rig.start()
        await rig.voice(1)
        rig.sensor.startSpeaking()
        await rig.step(1.5)
        await rig.player.waitUntilPlaying(2)

        rig.conductor.skip()

        #expect(rig.player.stops == 1)
        #expect(rig.lines.map(\.status) == [.done, .skipped, .skipped, .notReached])
        await rig.step()
        await rig.player.waitUntilPlaying(3)
        #expect(rig.player.lines.last?.text == texts[3])
        await rig.stop()
    }

    @Test func overlapPicksCeilNOverThreeWithASeededRNG() {
        // Six user lines, each followed by a voice line: ⌈6/3⌉ = 2 pairs.
        let roles = Array(repeating: [TestCallRole.you, .a, .you, .b], count: 3).flatMap { $0 }
        func picks(_ roles: [TestCallRole], seed: UInt64, overlap: Bool = true) -> [Int] {
            Rig(roles, overlap: overlap, seed: seed).lines.filter(\.overlapped).map(\.index)
        }

        #expect(picks(roles, seed: 7) == picks(roles, seed: 7))
        let all = (UInt64(1)...20).map { picks(roles, seed: $0) }
        for lines in all {
            #expect(lines.count == 4)
            for pair in stride(from: 0, to: lines.count, by: 2) {
                #expect(roles[lines[pair] - 1] == .you)
                #expect(lines[pair + 1] == lines[pair] + 1)
            }
        }
        #expect(Set(all).count > 1)
        #expect(picks(roles, seed: 7, overlap: false).isEmpty)
        // A user line followed by another user line, or ending the script, is never picked.
        #expect(picks([.you, .you, .a, .you], seed: 7) == [2, 3])
    }

    // MARK: - Stop and sleep

    @Test(arguments: [EndReason.stop, .sleep])
    func endMarksTheRunningLineStoppedAndTheRestNotReached(_ reason: EndReason) async {
        let rig = Rig()
        rig.start()
        await rig.voice(1)
        await rig.userReads()
        await rig.player.waitUntilPlaying(2)
        await rig.step(1)

        rig.conductor.end(reason)

        let statuses: [TestCallLineStatus] = [.done, .done, .stopped, .notReached, .notReached, .notReached]
        #expect(rig.player.stops == 1)
        #expect(rig.lines.map(\.status) == statuses)
        await rig.advance()
        await rig.done()
        #expect(rig.lines.map(\.status) == statuses)
        #expect(await rig.events() == [.line(1, .voiceSpeaking(.a)), .line(2, .yourTurn), .line(3, .voiceSpeaking(.b))])
    }

    @Test func endDuringAnOverlapStopsBothLines() async {
        let rig = Rig([.a, .you, .b, .a], overlap: true)
        rig.start()
        await rig.voice(1)
        rig.sensor.startSpeaking()
        await rig.step(1.5)
        await rig.player.waitUntilPlaying(2)

        rig.conductor.end(.sleep)

        #expect(rig.lines.map(\.status) == [.done, .stopped, .stopped, .notReached])
        await rig.advance()
        await rig.done()
        #expect(rig.lines.map(\.status) == [.done, .stopped, .stopped, .notReached])
    }

    // MARK: - `say` failures and capture

    @Test func twoConsecutiveSayFailuresEndTheScript() async {
        let rig = Rig()
        rig.start()
        await rig.player.waitUntilPlaying(1)
        rig.player.fail()
        await rig.step()
        rig.conductor.skip()
        await rig.step()
        await rig.player.waitUntilPlaying(2)
        rig.player.fail()
        await rig.advance()
        await rig.done()

        #expect(rig.lines.map(\.status) == [.skipped, .skipped, .skipped, .notReached, .notReached, .notReached])
        #expect(rig.lines.map(\.skipReason) == [.voiceFailed, .skipped, .voiceFailed, nil, nil, nil])
        #expect(await rig.events() == [
            .line(1, .voiceSpeaking(.a)), .skipped(1, .voiceFailed),
            .line(2, .yourTurn), .skipped(2, .skipped),
            .line(3, .voiceSpeaking(.b)), .skipped(3, .voiceFailed),
            .voicesFailed, .finished,
        ])
    }

    @Test func oneSayFailureOnlySkipsItsLine() async {
        let rig = Rig()
        rig.start()
        await rig.player.waitUntilPlaying(1)
        rig.player.fail()
        await rig.step()

        #expect(rig.lines[0].status == .skipped)
        #expect(rig.lines[0].skipReason == .voiceFailed)
        rig.conductor.skip()
        await rig.step()
        // Line 3 plays, so line 4's failure is the first in a row again.
        await rig.voice(2)
        await rig.player.waitUntilPlaying(3)
        rig.player.fail()
        await rig.step()

        #expect(rig.lines[3].skipReason == .voiceFailed)
        await rig.stop()
        let events = await rig.events()
        #expect(events.contains(.line(5, .yourTurn)))
        #expect(!events.contains(.voicesFailed))
    }

    @Test func missingSystemAudioAfterAVoiceLineEmitsCaptureMissing() async {
        let rig = Rig([.a, .b, .a])
        rig.sensor.hearsVoices = false
        rig.start()
        await rig.voice(1)
        // Heard last during line 1, before line 2 started.
        rig.sensor.lastAudible = origin + 2
        await rig.voice(2)
        await rig.player.waitUntilPlaying(3)
        await rig.step(3)
        rig.sensor.lastAudible = rig.now - 1
        rig.player.finish()
        await rig.advance()
        await rig.done()

        #expect(rig.lines.map(\.status) == [.done, .done, .done])
        #expect(await rig.events() == [
            .line(1, .voiceSpeaking(.a)), .captureMissing(1),
            .line(2, .voiceSpeaking(.b)), .captureMissing(2),
            .line(3, .voiceSpeaking(.a)), .finished,
        ])
    }

    // MARK: - The whole script

    @Test func finishedAfterTheLastLine() async {
        let rig = Rig()
        rig.start()
        await rig.voice(1)
        await rig.userReads()
        await rig.voice(2)
        await rig.voice(3)
        await rig.userReads()
        await rig.player.waitUntilPlaying(4)
        await rig.step(3)
        rig.player.finish()
        await rig.advance()
        await rig.done()

        #expect(rig.lines.map(\.status) == Array(repeating: .done, count: 6))
        #expect(rig.lines.map(\.index) == [1, 2, 3, 4, 5, 6])
        #expect(await rig.events() == [
            .line(1, .voiceSpeaking(.a)), .line(2, .yourTurn), .line(3, .voiceSpeaking(.b)),
            .line(4, .voiceSpeaking(.a)), .line(5, .yourTurn), .line(6, .voiceSpeaking(.b)), .finished,
        ])
    }

    @Test func pollsEvery100ms() async {
        let rig = Rig()
        rig.start()
        await rig.player.waitUntilPlaying(1)
        await rig.step()
        await rig.step()
        rig.player.finish()
        await rig.step()
        await rig.step()
        await rig.step()

        // One sleep per wake, while a voice plays and while the user is awaited.
        #expect(rig.clock.sleeps == Array(repeating: .milliseconds(100), count: 6))
        await rig.stop()
    }

    @Test func logsIdsAndReasonsNeverScriptText() async {
        let sink = CapturingLogSink()
        let rig = Rig()

        await logging(to: sink) {
            rig.start()
            await rig.player.waitUntilPlaying(1)
            rig.player.fail()
            await rig.step()
            await rig.step(20)
            await rig.voice(2)
            await rig.voice(3)
            rig.conductor.skip()
            await rig.step()
            await rig.player.waitUntilPlaying(4)
            await rig.stop()
        }

        #expect(sink.lines == [
            "INFO meeting test call: voice substituted Karen->Moira",
            "INFO meeting test call: line 1 skipped (voice failed)",
            "INFO meeting test call: line 2 skipped (no speech)",
            "INFO meeting test call: line 5 skipped (skip)",
        ])
        let script = Set(rig.scenario.lines.flatMap { words($0.text) })
        for line in sink.lines {
            #expect(script.isDisjoint(with: words(line)), "\(line)")
        }
    }
}

// MARK: - Harness

private func words(_ text: String) -> [String] {
    text.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
}

/// `Log.withSinks` around a main-actor body.
private func logging(to sink: CapturingLogSink, _ body: @MainActor @Sendable () async -> Void) async {
    await Log.withSinks(debug: true, sinks: [sink]) { await body() }
}

/// Drains a finished stream off the main actor.
private func drain(_ events: AsyncStream<ConductorEvent>) async -> [ConductorEvent] {
    var all: [ConductorEvent] = []
    for await event in events { all.append(event) }
    return all
}

/// A conductor over a scripted scenario, fake player and fake sensor on one `VirtualClock`.
@MainActor
private final class Rig {
    let clock: RecordingClock
    let sensor: FakeSensor
    let player: FakePlayer
    let scenario: TestScenario
    let conductor: TestCallConductor
    private var task: Task<Void, Never>?

    init(_ roles: [TestCallRole] = sixLines, overlap: Bool = false, seed: UInt64 = 1) {
        let clock = RecordingClock()
        let base = clock.base
        self.clock = clock
        sensor = FakeSensor { origin + base.now }
        player = FakePlayer { origin + base.now }
        scenario = TestScenario(
            id: "planning-check",
            revision: 1,
            title: "Planning check",
            voices: [
                VoiceRole(role: .a, character: "Tom", requested: "Daniel"),
                VoiceRole(role: .b, character: "Priya", requested: "Karen"),
            ],
            lines: roles.enumerated().map { ScenarioLine(role: $1, text: texts[$0 % texts.count]) }
        )
        var rng = SeededRandom(seed: seed)
        conductor = TestCallConductor(
            scenario: scenario,
            casting: casting,
            overlap: overlap,
            player: player,
            sensor: sensor,
            clock: clock,
            rng: &rng
        )
    }

    var now: Double { sensor.meetingTime }
    var lines: [RunLine] { conductor.result.lines }

    func start() {
        task = Task { await conductor.run() }
    }

    /// Once the conductor sleeps, moves time on: it wakes once, `seconds` later.
    func advance(_ seconds: Double = 0.1) async {
        await clock.base.waitUntilSleeping()
        clock.base.advance(by: seconds)
    }

    /// `advance`, then waits until the conductor has handled the wake and sleeps again.
    func step(_ seconds: Double = 0.1) async {
        await advance(seconds)
        await clock.base.waitUntilSleeping()
    }

    /// The `n`th `say` speaks for 3 s and exits normally; the conductor moves on.
    func voice(_ n: Int) async {
        await player.waitUntilPlaying(n)
        await step(3)
        player.finish()
        await step()
    }

    /// The user reads for 2 s and pauses until the hand-over.
    func userReads() async {
        sensor.startSpeaking()
        await step(2)
        sensor.stopSpeaking()
        await step(1.2)
    }

    /// Stop, then waits for `run()` to return.
    func stop() async {
        conductor.end(.stop)
        await advance()
        await done()
    }

    func done() async {
        await task?.value
    }

    func events() async -> [ConductorEvent] {
        await drain(conductor.events)
    }
}

/// `say` that runs until the test finishes or fails it, or the conductor stops it.
@MainActor
private final class FakePlayer: SpeechPlaying {
    private(set) var lines: [VoiceLine] = []
    private(set) var launches: [Double] = []
    private(set) var playbacks: [Playback] = []
    private(set) var stops = 0
    private let meetingTime: () -> Double
    private var running: CheckedContinuation<Playback, Never>?
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(meetingTime: @escaping () -> Double) {
        self.meetingTime = meetingTime
    }

    func play(_ line: VoiceLine) async -> Playback {
        lines.append(line)
        launches.append(meetingTime())
        let ready = waiters.filter { $0.count <= lines.count }
        waiters.removeAll { $0.count <= lines.count }
        for waiter in ready { waiter.continuation.resume() }
        return await withCheckedContinuation { running = $0 }
    }

    func stop() {
        stops += 1
        exit(normally: false)
    }

    func finish() { exit(normally: true) }

    func fail() { exit(normally: false) }

    /// Returns once `play` has been called `count` times.
    func waitUntilPlaying(_ count: Int) async {
        guard lines.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    private func exit(normally: Bool) {
        guard let continuation = running, let launched = launches.last else { return }
        running = nil
        let playback = Playback(launched: launched, exited: meetingTime(), normalExit: normally)
        playbacks.append(playback)
        continuation.resume(returning: playback)
    }
}

/// Microphone spans and tap state the test sets.
@MainActor
private final class FakeSensor: UserSpeechSensing {
    /// Closed spans.
    var spans: [ClosedRange<Double>] = []
    var isSpeaking = false
    /// While true, the tap has just heard audio; otherwise it last heard `lastAudible`.
    var hearsVoices = true
    var lastAudible: Double?
    private var openSince: Double?
    private let time: () -> Double

    init(meetingTime: @escaping () -> Double) {
        time = meetingTime
    }

    var meetingTime: Double { time() }
    var speechSpans: [ClosedRange<Double>] { spans + (openSince.map { [$0...meetingTime] } ?? []) }
    var lastAudibleSystemAudio: Double? { hearsVoices ? meetingTime : lastAudible }

    func startSpeaking() {
        openSince = meetingTime
        isSpeaking = true
    }

    func stopSpeaking() {
        if let start = openSince { spans.append(start...meetingTime) }
        openSince = nil
        isSpeaking = false
    }
}

/// A `VirtualClock` that also records every duration slept on.
private final class RecordingClock: MWSupport.Clock, @unchecked Sendable {
    let base = VirtualClock()
    private let lock = NSLock()
    private var durations: [Duration] = []

    var now: TimeInterval { base.now }
    var sleeps: [Duration] { lock.withLock { durations } }

    func sleep(for duration: Duration) async throws {
        lock.withLock { durations.append(duration) }
        try await base.sleep(for: duration)
    }
}
