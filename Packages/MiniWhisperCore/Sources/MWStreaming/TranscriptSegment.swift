import Foundation

/// One recognised word; times are seconds from the session's audio origin.
public struct TranscriptWord: Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A finalised span of speech from one provider speaker. Adapters emit it beside the
/// matching `.final`, so it never feeds the dictation transcript.
public struct TranscriptSegment: Sendable, Equatable {
    public var text: String
    public var words: [TranscriptWord]
    /// Provider label; nil when diarization is off or the provider could not tell.
    public var speaker: String?
    /// AssemblyAI only: the turn a later `SpeakerRevision` refers to.
    public var turnOrder: Int?
    public var start: Double
    public var end: Double

    public init(
        text: String,
        words: [TranscriptWord] = [],
        speaker: String? = nil,
        turnOrder: Int? = nil,
        start: Double,
        end: Double
    ) {
        self.text = text
        self.words = words
        self.speaker = speaker
        self.turnOrder = turnOrder
        self.start = start
        self.end = end
    }
}

/// The provider re-labelled the speakers of an earlier turn.
public struct SpeakerRevision: Sendable, Equatable {
    public var turnOrder: Int
    public var speaker: String
    public var words: [TranscriptWord]

    public init(turnOrder: Int, speaker: String, words: [TranscriptWord] = []) {
        self.turnOrder = turnOrder
        self.speaker = speaker
        self.words = words
    }
}

/// The provider will end the session: at a known time, or soon.
public enum SessionLimit: Sendable, Equatable {
    case expiresAt(Date)
    case warning
}
