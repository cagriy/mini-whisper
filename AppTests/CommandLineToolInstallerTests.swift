import Foundation
import Testing
@testable import MiniWhisper

@Suite struct CommandLineToolInstallerTests {
    private static let app = "/Applications/Mini Whisper.app"

    @Test func scriptBakesTheBundlePath() {
        let script = CommandLineToolInstaller.script(appPath: Self.app)

        #expect(script.hasPrefix("#!/bin/sh\n"))
        #expect(script.contains("APP='/Applications/Mini Whisper.app'\n"))
        #expect(script.hasSuffix("exec \"$APP/Contents/MacOS/Mini Whisper\" \"$@\"\n"))
    }

    @Test func scriptFallsBackToTheBundleID() {
        let script = CommandLineToolInstaller.script(appPath: Self.app)

        #expect(script.contains("if [ ! -x \"$APP/Contents/MacOS/Mini Whisper\" ]; then"))
        #expect(script.contains("path to application id \"com.ips.mini-whisper\""))
    }

    @Test func aPathWithASingleQuoteIsEscaped() {
        let script = CommandLineToolInstaller.script(appPath: "/Users/alex/Bob's Apps/Mini Whisper.app")

        #expect(script.contains("APP='/Users/alex/Bob'\\''s Apps/Mini Whisper.app'\n"))
    }

    @Test func installCommandMakesTheDirectoryWritesTheFileAndChmods755() {
        let script = CommandLineToolInstaller.script(appPath: Self.app)

        let command = CommandLineToolInstaller.installCommand(script: script)

        let quoted = "'" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"
        #expect(command == """
            mkdir -p /usr/local/bin && rm -f /usr/local/bin/mini-whisper \
            && printf '%s' \(quoted) > /usr/local/bin/mini-whisper && chmod 755 /usr/local/bin/mini-whisper
            """)
        #expect(!command.contains("ln "))
    }

    @Test func appleScriptEscapesQuotesAndBackslashes() {
        let source = CommandLineToolInstaller.appleScript(command: #"printf '%s' 'a "b" \c'"#)

        #expect(source == #"do shell script "printf '%s' 'a \"b\" \\c'" with administrator privileges"#)
    }

    @Test func isInstalledReadsTheWrapper() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wrapper = directory.appendingPathComponent("mini-whisper")
        #expect(!CommandLineToolInstaller.isInstalled(at: wrapper.path))

        try Data("#!/bin/sh\necho other\n".utf8).write(to: wrapper)
        #expect(!CommandLineToolInstaller.isInstalled(at: wrapper.path))

        try Data(CommandLineToolInstaller.script(appPath: Self.app).utf8).write(to: wrapper)
        #expect(CommandLineToolInstaller.isInstalled(at: wrapper.path))
    }

    @Test func mcpCommandUsesTheShortNameWhenInstalled() {
        let command = CommandLineToolInstaller.mcpCommand(installed: true, binaryPath: Self.app + "/Contents/MacOS/Mini Whisper")

        #expect(command == "claude mcp add --transport stdio mini-whisper -- mini-whisper mcp")
    }

    @Test func mcpCommandUsesTheFullBinaryPathOtherwise() {
        let command = CommandLineToolInstaller.mcpCommand(installed: false, binaryPath: Self.app + "/Contents/MacOS/Mini Whisper")

        #expect(command == "claude mcp add --transport stdio mini-whisper -- '/Applications/Mini Whisper.app/Contents/MacOS/Mini Whisper' mcp")
    }
}
