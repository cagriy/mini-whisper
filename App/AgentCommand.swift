import Foundation
import MWAgentAccess
import MWMeetings

/// `Mini Whisper meetings …` and `Mini Whisper mcp` (design §5.3, R21): run from `main.swift`
/// before `NSApplication` exists, so an agent never starts the GUI or capture. Several may run
/// beside the GUI; `SingleInstanceGuard` is not consulted.
struct AgentCommand {
    enum Kind: Equatable {
        /// The arguments after `meetings`.
        case meetings([String])
        case mcp
    }

    let kind: Kind

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// The Markdown's `generator`, shared with the window's exports so both print the same text.
    static var generator: String { "Mini Whisper \(version)" }

    /// nil unless the first argument names a command, so `--debug` and Finder's `-psn_…`
    /// start the GUI.
    init?(arguments: [String]) {
        guard arguments.count > 1 else { return nil }
        switch arguments[1] {
        case "meetings": kind = .meetings(Array(arguments.dropFirst(2)))
        case "mcp": kind = .mcp
        default: return nil
        }
    }

    /// The process exit status.
    @MainActor
    func run() -> Int32 {
        let store = MeetingStore(directory: AppDelegate.configDirectory.appendingPathComponent("meetings", isDirectory: true))
        switch kind {
        case .meetings(let arguments):
            return MeetingsCLI(reader: AgentMeetings(store), generator: Self.generator)
                .run(arguments, out: Self.write(to: .standardOutput), err: Self.write(to: .standardError))
        case .mcp:
            return MCPServer(reader: AgentMeetings(store), version: Self.version)
                .run(readLine: { readLine() }, write: Self.write(to: .standardOutput))
        }
    }

    /// `FileHandle` writes are unbuffered, so each MCP reply reaches the client at once.
    private static func write(to handle: FileHandle) -> (String) -> Void {
        { text in try? handle.write(contentsOf: Data(text.utf8)) }
    }
}
