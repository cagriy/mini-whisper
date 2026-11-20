import Foundation
import MWMeetings

/// One meeting's voice of a person on the local route.
public struct LocalSample: Codable, Sendable, Equatable {
    public var meeting: UUID
    public var at: Date
    /// The speech behind the vector.
    public var seconds: Double
    public var vector: VoiceVector

    public init(meeting: UUID, at: Date, seconds: Double, vector: VoiceVector) {
        self.meeting = meeting
        self.at = at
        self.seconds = seconds
        self.vector = vector
    }
}

/// A voice identifier Speechmatics returned for a person, opaque and sent back only to it.
public struct SpeechmaticsIdentifier: Codable, Sendable, Equatable {
    public var meeting: UUID
    public var at: Date
    public var identifier: String

    public init(meeting: UUID, at: Date, identifier: String) {
        self.meeting = meeting
        self.at = at
        self.identifier = identifier
    }
}

/// One entry of `~/.config/mini-whisper/voices.json`.
public struct Person: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var isUser: Bool
    public var createdAt: Date
    public var lastHeard: Date?
    /// The ids of people merged into this one, so Forget still finds their links in old meetings.
    public var aliases: [UUID]
    /// At most `SampleSet.capacity`, one per meeting.
    public var local: [LocalSample]
    /// The newest identifier per tier, keyed `"standard"` / `"enhanced"`.
    public var speechmatics: [String: SpeechmaticsIdentifier]
    /// Confirmed under Speechmatics: an `mw:` label of this person is applied, not suggested.
    public var speechmaticsTrusted: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        isUser: Bool = false,
        createdAt: Date,
        lastHeard: Date? = nil,
        aliases: [UUID] = [],
        local: [LocalSample] = [],
        speechmatics: [String: SpeechmaticsIdentifier] = [:],
        speechmaticsTrusted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isUser = isUser
        self.createdAt = createdAt
        self.lastHeard = lastHeard
        self.aliases = aliases
        self.local = local
        self.speechmatics = speechmatics
        self.speechmaticsTrusted = speechmaticsTrusted
    }
}
