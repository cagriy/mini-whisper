import Foundation
import MWMeetings

public enum PauseReason: Sendable, Equatable {
    case user
    /// The Mac went to sleep; the meeting stays paused until Resume.
    case sleep
}

public enum MeetingState: Sendable, Equatable {
    case idle
    case starting
    case recording
    case paused(PauseReason)
    case stopping
    case stopped
}

/// The stopped window's summary panel (design §3 R12).
public enum SummaryState: Sendable, Equatable {
    /// No summary, and why: no Anthropic key, or nothing was transcribed.
    case none(String)
    case writing
    case ready(Summary)
    /// The request failed or was declined; *Summarise* stays available.
    case failed(String)
}

/// The capture chip and the silence hint (design §3 R2, §5.6).
public enum SystemAudioState: Sendable, Equatable {
    case on
    /// The meeting continues on the microphone alone.
    case unavailable(String)
    /// A minute of the user speaking with nothing heard from other apps.
    case silentHint
}

/// Everything the meeting window renders, in order (design §5.3).
public enum MeetingEvent: Sendable, Equatable {
    case state(MeetingState)
    case segmentAdded(Segment)
    case segmentUpdated(Segment)
    /// `speaker` is the user's id while the microphone gate is open, else nil.
    case partial(String, speaker: Int?)
    case speakers([SpeakerLabel])
    case marker(Marker)
    case note(Note)
    case connection(ConnectionState)
    /// Meeting seconds, paused spans included.
    case elapsed(Double)
    /// The live transcription estimate in dollars.
    case cost(Double)
    case summary(SummaryState)
    case systemAudio(SystemAudioState)
    /// A failure the meeting survives, such as a transcript write error.
    case error(String)
}

public enum MeetingError: Error, Equatable, LocalizedError {
    /// Neither a Speechmatics nor an AssemblyAI key is stored.
    case noEngineKey

    public var errorDescription: String? {
        switch self {
        case .noEngineKey: "Add a Speechmatics or AssemblyAI key under Keys."
        }
    }
}
