import Foundation

/// `prompt.txt` and `transcribe_prompt.txt`: the bundled defaults are copied in on first
/// use and the files are re-read on demand, as `config.py:get_prompt` does (F2).
public struct PromptFiles: Sendable {
    private let directory: URL
    private let bundledCleanup: URL
    private let bundledTranscribe: URL

    public init(directory: URL, bundledCleanup: URL, bundledTranscribe: URL) {
        self.directory = directory
        self.bundledCleanup = bundledCleanup
        self.bundledTranscribe = bundledTranscribe
    }

    /// Exposed so Settings' “Open in Editor” can hand the file to the user's editor
    /// without duplicating the file names.
    public var cleanupPromptURL: URL { directory.appendingPathComponent("prompt.txt") }
    public var transcribeInstructionsURL: URL {
        directory.appendingPathComponent("transcribe_prompt.txt")
    }

    public func cleanupPrompt() throws -> String {
        try read(cleanupPromptURL, bundled: bundledCleanup)
    }

    public func transcribeInstructions() throws -> String {
        try read(transcribeInstructionsURL, bundled: bundledTranscribe)
    }

    public func write(cleanupPrompt: String) throws {
        try write(cleanupPrompt, to: cleanupPromptURL)
    }

    public func write(transcribeInstructions: String) throws {
        try write(transcribeInstructions, to: transcribeInstructionsURL)
    }

    private func read(_ url: URL, bundled: URL) throws -> String {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: bundled, to: url)
        }
        return try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
