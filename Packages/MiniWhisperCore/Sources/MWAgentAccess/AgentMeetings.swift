import Foundation
import MWMeetings

/// The reader the CLI and MCP server get (design §5.3, R22): test meetings are absent. Ids
/// resolve against the filtered index, so a test meeting's id or prefix fails as unknown.
public struct AgentMeetings: MeetingReading {
    private let base: any MeetingReading

    public init(_ base: any MeetingReading) {
        self.base = base
    }

    public func index() throws -> [IndexEntry] {
        try base.index().filter { $0.test == nil }
    }

    /// A test meeting throws what a missing meeting folder throws.
    public func load(_ id: UUID) throws -> LoadedMeeting {
        let loaded = try base.load(id)
        guard loaded.meeting.test == nil else { throw CocoaError(.fileReadNoSuchFile) }
        return loaded
    }
}
