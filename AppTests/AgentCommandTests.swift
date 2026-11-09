import Foundation
import Testing
@testable import MiniWhisper

@Suite struct AgentCommandTests {
    private static let binary = "/Applications/Mini Whisper.app/Contents/MacOS/Mini Whisper"

    @Test func meetingsSubcommandIsRecognised() {
        let command = AgentCommand(arguments: [Self.binary, "meetings", "search", "pricing", "--json"])
        #expect(command?.kind == .meetings(["search", "pricing", "--json"]))
    }

    @Test func mcpIsRecognised() {
        #expect(AgentCommand(arguments: [Self.binary, "mcp"])?.kind == .mcp)
    }

    @Test func debugFlagStartsTheGUI() {
        #expect(AgentCommand(arguments: [Self.binary, "--debug"]) == nil)
        #expect(AgentCommand(arguments: [Self.binary, "--debug", "meetings", "list"]) == nil)
    }

    @Test func noArgumentsStartsTheGUI() {
        #expect(AgentCommand(arguments: [Self.binary]) == nil)
        #expect(AgentCommand(arguments: []) == nil)
    }

    @Test func finderProcessSerialNumberIsIgnored() {
        #expect(AgentCommand(arguments: [Self.binary, "-psn_0_123"]) == nil)
    }
}
