import Foundation
import MWTestCall

/// Plays voice lines with `/usr/bin/say`, launched by absolute path with an argument array and no
/// shell (design §5.7).
@MainActor
final class SayProcessPlayer: SpeechPlaying {
    nonisolated static let say = URL(fileURLWithPath: "/usr/bin/say")

    let executable: URL
    private let meetingTime: @MainActor () -> Double
    private var running: Process?

    init(executable: URL = SayProcessPlayer.say, meetingTime: @escaping @MainActor () -> Double) {
        self.executable = executable
        self.meetingTime = meetingTime
    }

    static func arguments(for line: VoiceLine) -> [String] {
        ["-v", line.voice, line.text]
    }

    func play(_ line: VoiceLine) async -> Playback {
        guard VoiceCatalog.isAllowed(line.voice) else {
            let now = meetingTime()
            return Playback(launched: now, exited: now, normalExit: false)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(for: line)
        // `say` reads its text from the arguments; the idle pipe keeps it off the app's stdin.
        process.standardInput = Pipe()
        var launched: Double?
        let exitedNormally = await withCheckedContinuation { continuation in
            process.terminationHandler = {
                continuation.resume(returning: $0.terminationReason == .exit && $0.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                // Never launched, so the termination handler never runs.
                return continuation.resume(returning: false)
            }
            launched = meetingTime()
            running = process
        }
        if running === process { running = nil }
        let exited = meetingTime()
        return Playback(launched: launched ?? exited, exited: exited, normalExit: exitedNormally)
    }

    func stop() {
        running?.terminate()
    }
}
