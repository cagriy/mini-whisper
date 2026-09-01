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
        transcribe: String = "Transcribe verbatim.\n"
    ) throws -> Fixture {
        let directory = try TempDirectory()
        let bundle = try TempDirectory()
        try cleanup.write(to: bundle.file("default_prompt.txt"), atomically: true, encoding: .utf8)
        try transcribe.write(
            to: bundle.file("default_transcribe_prompt.txt"), atomically: true, encoding: .utf8
        )
        return Fixture(
            directory: directory,
            bundle: bundle,
            files: PromptFiles(
                directory: directory.url,
                bundledCleanup: bundle.file("default_prompt.txt"),
                bundledTranscribe: bundle.file("default_transcribe_prompt.txt")
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
}
