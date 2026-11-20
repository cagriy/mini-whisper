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
    /// A new summary is being written; this one is still current.
    case rewriting(Summary)
    /// Regeneration did not produce one; this one is still current.
    case kept(Summary, reason: String)
}

/// The capture chip and the silence hint (design §3 R2, §5.6).
public enum SystemAudioState: Sendable, Equatable {
    case on
    /// The meeting continues on the microphone alone.
    case unavailable(String)
    /// A minute of the user speaking with nothing heard from other apps.
    case silentHint
}

/// A test meeting's score (design §3 R20, §5.3).
public enum TestScoreState: Sendable, Equatable {
    case scored(TestCallRecord)
    /// No score file and no WER on the tag: the test call did not finish.
    case missing
    /// The score file fails to decode, or is gone although the tag has a WER.
    case unreadable
}

/// The prompt asking whether a meeting with no speech keeps recording.
public enum SilencePrompt: Sendable, Equatable {
    /// Open, re-sent every tick with the seconds left.
    case open(minutes: Int, secondsLeft: Int)
    case closed
    /// The countdown ran out; the coordinator stops the meeting.
    case expired
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
    /// A summary named the meeting; sent before its `.summary(.ready)`.
    case title(String)
    case systemAudio(SystemAudioState)
    /// A test meeting's score: on open, and once scored at Stop.
    case testScore(TestScoreState)
    case silence(SilencePrompt)
    /// A failure the meeting survives, such as a transcript write error.
    case error(String)
    /// An information line, shown once (design v8 R13).
    case notice(String)
    /// The provider keys with stored voice data; `active` while this session runs the route
    /// (design v8 §5 Interfaces).
    case voiceData(active: Bool, keys: Set<String>)
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
