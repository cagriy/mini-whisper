import Foundation

/// `prompt.txt`, `transcribe_prompt.txt` and `summary_prompt.txt`: the bundled defaults are
/// copied in on first use and the files are re-read on demand, as `config.py:get_prompt` does (F2).
public struct PromptFiles: SummaryPromptProviding {
    private let directory: URL
    private let bundledCleanup: URL
    private let bundledTranscribe: URL
    private let bundledSummary: URL?

    public init(directory: URL, bundledCleanup: URL, bundledTranscribe: URL, bundledSummary: URL? = nil) {
        self.directory = directory
        self.bundledCleanup = bundledCleanup
        self.bundledTranscribe = bundledTranscribe
        self.bundledSummary = bundledSummary
    }

    /// Exposed so Settings' “Open in Editor” can hand the file to the user's editor
    /// without duplicating the file names.
    public var cleanupPromptURL: URL { directory.appendingPathComponent("prompt.txt") }
    public var transcribeInstructionsURL: URL {
        directory.appendingPathComponent("transcribe_prompt.txt")
    }
    public var summaryPromptURL: URL { directory.appendingPathComponent("summary_prompt.txt") }

    public func cleanupPrompt() throws -> String {
        try read(cleanupPromptURL, bundled: bundledCleanup)
    }

    public func transcribeInstructions() throws -> String {
        try read(transcribeInstructionsURL, bundled: bundledTranscribe)
    }

    public func summaryPrompt() throws -> String {
        try read(summaryPromptURL, bundled: bundledSummary)
    }

    public func write(cleanupPrompt: String) throws {
        try write(cleanupPrompt, to: cleanupPromptURL)
    }

    public func write(transcribeInstructions: String) throws {
        try write(transcribeInstructions, to: transcribeInstructionsURL)
    }

    public func write(summaryPrompt: String) throws {
        try write(summaryPrompt, to: summaryPromptURL)
    }

    public func restoreDefaultSummaryPrompt() throws {
        try write(String(contentsOf: try required(bundledSummary), encoding: .utf8), to: summaryPromptURL)
    }

    /// The default summary prompts shipped before the topic-based one, final newline included.
    public static let legacySummaryDefaults: [String] = [
        """
        You summarise a meeting for the person who attended it. Write four sections with these \
        exact headings: `## Summary`, `## Decisions`, `## Action items`, `## Open questions`. \
        Summary is one short paragraph. Decisions, Action items and Open questions are bullet \
        lists; an action item starts with the owner's name in bold when the transcript names one. \
        Use the speaker names exactly as given. Do not invent names, decisions, owners or dates; \
        when something was discussed but not settled, list it under Open questions. The \
        attendee's own notes are provided separately and may be used as hints about what \
        mattered, never as transcript. Answer in the language of the transcript.

        """,
    ]

    /// Replaces a `summary_prompt.txt` that still holds a legacy default with the bundled one and
    /// says whether it did. Any other content is the user's: the file is not opened for writing.
    public func migrateSummaryPrompt() throws -> Bool {
        guard FileManager.default.fileExists(atPath: summaryPromptURL.path) else { return false }
        let stored = Self.trimmed(try String(contentsOf: summaryPromptURL, encoding: .utf8))
        guard Self.legacySummaryDefaults.contains(where: { Self.trimmed($0) == stored }) else {
            return false
        }
        try restoreDefaultSummaryPrompt()
        return true
    }

    private func read(_ url: URL, bundled: URL?) throws -> String {
        if !FileManager.default.fileExists(atPath: url.path) {
            let source = try required(bundled)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: url)
        }
        return Self.trimmed(try String(contentsOf: url, encoding: .utf8))
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private func required(_ bundled: URL?) throws -> URL {
        guard let bundled else { throw CocoaError(.fileReadNoSuchFile) }
        return bundled
    }
}
