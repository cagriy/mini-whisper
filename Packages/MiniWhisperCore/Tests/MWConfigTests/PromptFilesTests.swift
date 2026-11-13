import Foundation
import Testing
@testable import MWConfig
import MWTestSupport

@Suite struct PromptFilesTests {
    private struct Fixture {
        let directory: TempDirectory
        let bundle: TempDirectory
        let files: PromptFiles
    }

    private func makeFixture(
        cleanup: String = "  Clean this up.  \n",
        transcribe: String = "Transcribe verbatim.\n",
        summary: String = "Summarise the meeting.\n"
    ) throws -> Fixture {
        let directory = try TempDirectory()
        let bundle = try TempDirectory()
        try cleanup.write(to: bundle.file("default_prompt.txt"), atomically: true, encoding: .utf8)
        try transcribe.write(
            to: bundle.file("default_transcribe_prompt.txt"), atomically: true, encoding: .utf8
        )
        try summary.write(to: bundle.file("default_summary_prompt.txt"), atomically: true, encoding: .utf8)
        return Fixture(
            directory: directory,
            bundle: bundle,
            files: PromptFiles(
                directory: directory.url,
                bundledCleanup: bundle.file("default_prompt.txt"),
                bundledTranscribe: bundle.file("default_transcribe_prompt.txt"),
                bundledSummary: bundle.file("default_summary_prompt.txt")
            )
        )
    }

    @Test func copiesBundledDefaultsOnFirstRun() throws {
        let fixture = try makeFixture()

        _ = try fixture.files.cleanupPrompt()
        _ = try fixture.files.transcribeInstructions()

        #expect(
            try String(contentsOf: fixture.directory.file("prompt.txt"), encoding: .utf8)
                == "  Clean this up.  \n"
        )
        #expect(
            try String(contentsOf: fixture.directory.file("transcribe_prompt.txt"), encoding: .utf8)
                == "Transcribe verbatim.\n"
        )
    }

    @Test func readsTrimmedContent() throws {
        let fixture = try makeFixture()

        #expect(try fixture.files.cleanupPrompt() == "Clean this up.")
        #expect(try fixture.files.transcribeInstructions() == "Transcribe verbatim.")
    }

    @Test func writeReplacesContent() throws {
        let fixture = try makeFixture()
        _ = try fixture.files.cleanupPrompt()

        try fixture.files.write(cleanupPrompt: "Keep shell commands verbatim.")
        try fixture.files.write(transcribeInstructions: "British English.")

        #expect(try fixture.files.cleanupPrompt() == "Keep shell commands verbatim.")
        #expect(try fixture.files.transcribeInstructions() == "British English.")
    }

    @Test func seedsSummaryPromptFromTheBundledDefault() throws {
        let fixture = try makeFixture()

        #expect(try fixture.files.summaryPrompt() == "Summarise the meeting.")
        #expect(
            try String(contentsOf: fixture.directory.file("summary_prompt.txt"), encoding: .utf8)
                == "Summarise the meeting.\n"
        )
    }

    @Test func writeSummaryPromptReplacesContent() throws {
        let fixture = try makeFixture()
        _ = try fixture.files.summaryPrompt()

        try fixture.files.write(summaryPrompt: "List decisions only.")

        #expect(try fixture.files.summaryPrompt() == "List decisions only.")
    }

    @Test func restoreDefaultSummaryPromptOverwritesAnEdit() throws {
        let fixture = try makeFixture()
        try fixture.files.write(summaryPrompt: "List decisions only.")

        try fixture.files.restoreDefaultSummaryPrompt()

        #expect(try fixture.files.summaryPrompt() == "Summarise the meeting.")
        #expect(
            try String(contentsOf: fixture.directory.file("summary_prompt.txt"), encoding: .utf8)
                == "Summarise the meeting.\n"
        )
    }

    @Test func promptFilesIsASummaryPromptProvider() throws {
        let fixture = try makeFixture()
        let provider: any SummaryPromptProviding = fixture.files

        #expect(try provider.summaryPrompt() == "Summarise the meeting.")
    }

    // MARK: - Summary prompt migration

    /// `git show e64ed39:App/Resources/default_summary_prompt.txt`, final newline included.
    private static let shippedAtE64ed39 = """
        You summarise a meeting for the person who attended it. Write four sections with these \
        exact headings: `## Summary`, `## Decisions`, `## Action items`, `## Open questions`. \
        Summary is one short paragraph. Decisions, Action items and Open questions are bullet \
        lists; an action item starts with the owner's name in bold when the transcript names one. \
        Use the speaker names exactly as given. Do not invent names, decisions, owners or dates; \
        when something was discussed but not settled, list it under Open questions. The \
        attendee's own notes are provided separately and may be used as hints about what \
        mattered, never as transcript. Answer in the language of the transcript.

        """

    private static let topicDefault = "Write the meeting up by topic.\n"

    @Test func legacyDefaultIsTheTextShippedAtE64ed39() {
        #expect(PromptFiles.legacySummaryDefaults.first == Self.shippedAtE64ed39)
    }

    @Test func migrationLeavesAMissingFileAlone() throws {
        let fixture = try makeFixture()

        #expect(try fixture.files.migrateSummaryPrompt() == false)
        #expect(!FileManager.default.fileExists(atPath: fixture.files.summaryPromptURL.path))
    }

    @Test func migrationReplacesTheLegacyDefault() throws {
        let fixture = try makeFixture(summary: Self.topicDefault)
        let file = fixture.files.summaryPromptURL
        try Data(PromptFiles.legacySummaryDefaults[0].utf8).write(to: file)

        #expect(try fixture.files.migrateSummaryPrompt() == true)
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.topicDefault)
    }

    /// Settings saves the prompt trimmed; an editor may leave blank lines around it.
    @Test(arguments: [
        Self.shippedAtE64ed39.trimmingCharacters(in: .whitespacesAndNewlines),
        "  \n  " + Self.shippedAtE64ed39 + "\n",
    ])
    func migrationMatchesIgnoringSurroundingWhitespace(stored: String) throws {
        let fixture = try makeFixture(summary: Self.topicDefault)
        let file = fixture.files.summaryPromptURL
        try Data(stored.utf8).write(to: file)

        #expect(try fixture.files.migrateSummaryPrompt() == true)
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.topicDefault)
    }

    @Test func migrationLeavesAnEditedFileByteForByte() throws {
        let fixture = try makeFixture()
        let file = fixture.files.summaryPromptURL
        let edited = Data((Self.shippedAtE64ed39 + "Also list the risks.\r\n").utf8)
        let saved = Date(timeIntervalSince1970: 1_700_000_000)
        try edited.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: saved], ofItemAtPath: file.path)

        #expect(try fixture.files.migrateSummaryPrompt() == false)
        #expect(try Data(contentsOf: file) == edited)
        #expect(
            try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == saved
        )
    }

    @Test func migrationThrowsOnAnUnreadableFileAndLeavesIt() throws {
        let fixture = try makeFixture()
        let file = fixture.files.summaryPromptURL
        let notUTF8 = Data([0xFF, 0xFE, 0xFD])
        try notUTF8.write(to: file)

        #expect(throws: (any Error).self) { try fixture.files.migrateSummaryPrompt() }
        #expect(try Data(contentsOf: file) == notUTF8)
    }

    @Test func migrationThrowsWithoutABundledDefaultAndLeavesTheLegacyFile() throws {
        let fixture = try makeFixture()
        let file = fixture.files.summaryPromptURL
        let legacy = Data(Self.shippedAtE64ed39.utf8)
        try legacy.write(to: file)
        try FileManager.default.removeItem(at: fixture.bundle.file("default_summary_prompt.txt"))

        #expect(throws: (any Error).self) { try fixture.files.migrateSummaryPrompt() }
        #expect(try Data(contentsOf: file) == legacy)
    }
}
