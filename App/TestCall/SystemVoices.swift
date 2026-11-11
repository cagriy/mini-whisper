import Foundation

/// The `say -v ?` listing that `VoiceCatalog.parse` reads, run off the main actor.
struct SystemVoices: Sendable {
    let executable: URL
    let arguments: [String]

    init(executable: URL = SayProcessPlayer.say, arguments: [String] = ["-v", "?"]) {
        self.executable = executable
        self.arguments = arguments
    }

    /// Empty when the tool cannot run, which casts no voices.
    func load() async -> String {
        await Task.detached { [executable, arguments] in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            guard (try? process.run()) != nil else { return "" }
            let data = try? output.fileHandleForReading.readToEnd()
            process.waitUntilExit()
            return String(decoding: data ?? Data(), as: UTF8.self)
        }.value
    }
}
