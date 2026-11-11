import Foundation
import Testing

import MWTestCall
@testable import MiniWhisper

/// A meeting clock that advances one second per read and counts the reads.
@MainActor
private final class MeetingTime {
    private(set) var reads = 0

    func read() -> Double {
        reads += 1
        return Double(reads)
    }
}

/// Stand-in executables take the place of `say`: real, trivial processes that play no audio.
@MainActor
@Suite struct SayProcessPlayerTests {
    private static let line = VoiceLine(text: "Then the remaining risk is the webhook.", voice: "Daniel")

    private static func player(_ path: String, _ time: MeetingTime) -> SayProcessPlayer {
        SayProcessPlayer(executable: URL(fileURLWithPath: path), meetingTime: time.read)
    }

    @Test func argumentsAreVoiceThenTextWithNoShell() {
        let line = VoiceLine(text: "Then the remaining risk…", voice: "Daniel")
        #expect(SayProcessPlayer.arguments(for: line) == ["-v", "Daniel", "Then the remaining risk…"])
        #expect(SayProcessPlayer(meetingTime: { 0 }).executable == URL(fileURLWithPath: "/usr/bin/say"))
    }

    /// `true` exits normally, so a normal exit would mean it ran.
    @Test(arguments: ["-o spoken.aiff", "Daniel; say hello", ""])
    func disallowedVoiceNameNeverLaunches(voice: String) async {
        let time = MeetingTime()
        let playback = await Self.player("/usr/bin/true", time).play(VoiceLine(text: "Hello.", voice: voice))
        #expect(playback == Playback(launched: 1, exited: 1, normalExit: false))
    }

    @Test func zeroExitIsNormal() async {
        let time = MeetingTime()
        let playback = await Self.player("/usr/bin/true", time).play(Self.line)
        #expect(playback == Playback(launched: 1, exited: 2, normalExit: true))
    }

    @Test func nonZeroExitIsAFailure() async {
        let time = MeetingTime()
        let playback = await Self.player("/usr/bin/false", time).play(Self.line)
        #expect(playback == Playback(launched: 1, exited: 2, normalExit: false))
    }

    @Test func missingExecutableIsAFailure() async {
        let time = MeetingTime()
        let playback = await Self.player("/nonexistent/say", time).play(Self.line)
        #expect(playback == Playback(launched: 1, exited: 1, normalExit: false))
    }

    @Test(.timeLimit(.minutes(1)))
    func stopTerminatesTheRunningProcess() async {
        let time = MeetingTime()
        let player = Self.player("/bin/cat", time)
        // `cat -v Daniel -` reads its stdin pipe, which nothing writes to, so only `stop()` ends it.
        let playing = Task { await player.play(VoiceLine(text: "-", voice: "Daniel")) }
        // The launch time is read in the same main-actor job that launches the process.
        while time.reads == 0 { await Task.yield() }
        player.stop()
        let playback = await playing.value
        #expect(playback == Playback(launched: 1, exited: 2, normalExit: false))
    }

    @Test func systemVoicesReturnsTheToolsOutput() async {
        let voices = SystemVoices(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["-v", "?"])
        #expect(await voices.load() == "-v ?\n")
    }

    @Test func systemVoicesIsEmptyWhenTheToolCannotRun() async {
        let voices = SystemVoices(executable: URL(fileURLWithPath: "/nonexistent/say"), arguments: ["-v", "?"])
        #expect(await voices.load() == "")
    }
}

/// Plays real speech through the speakers, so it is opt-in only. Command:
/// `TEST_RUNNER_MW_INTEGRATION=1 xcodebuild … test -only-testing:AppTests/SayProcessPlayerIntegrationTests`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MW_INTEGRATION"] == "1"))
struct SayProcessPlayerIntegrationTests {
    @Test func playsAShortLineWithANormalExit() async throws {
        let catalog = VoiceCatalog(voices: VoiceCatalog.parse(await SystemVoices().load()))
        let voice = try #require(catalog.english.first { VoiceCatalog.isAllowed($0.name) })
        let player = SayProcessPlayer { ProcessInfo.processInfo.systemUptime }
        let playback = await player.play(VoiceLine(text: "This is a test call.", voice: voice.name))
        #expect(playback.normalExit)
        #expect(playback.exited > playback.launched)
    }
}
