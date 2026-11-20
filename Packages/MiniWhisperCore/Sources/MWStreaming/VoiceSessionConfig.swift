/// R10: the people one Speechmatics session enrols, and how readily it prefers them.
public struct VoiceSessionConfig: Sendable, Equatable {
    public struct Speaker: Sendable, Equatable {
        /// `mw:<lowercase person UUID>`; never a name.
        public var label: String
        public var identifier: String

        public init(label: String, identifier: String) {
            self.label = label
            self.identifier = identifier
        }
    }

    public var speakers: [Speaker]
    public var sensitivity: Double

    public init(speakers: [Speaker], sensitivity: Double) {
        self.speakers = speakers
        self.sensitivity = sensitivity
    }
}

/// R12: one `SpeakersResult` entry, a session label and the identifiers made for it.
public struct ProviderSpeaker: Sendable, Equatable {
    public var label: String
    public var identifiers: [String]

    public init(label: String, identifiers: [String]) {
        self.label = label
        self.identifiers = identifiers
    }
}

/// A message a live session sends between audio chunks.
public enum EngineCommand: Sendable, Equatable {
    /// Speechmatics `GetSpeakers`, not final.
    case requestSpeakers
}
