public enum AudioEvent: Sendable, Equatable {
    case live
    case deviceChanged
    case stopped
}

public enum AudioBackendEvent: Sendable, Equatable {
    case configurationChanged
    case systemWillSleep
}

/// What a meeting needs to hear from a held engine, on a stream of its own because
/// `events` already has its consumer (`DictationController`).
public enum MeetingAudioEvent: Sendable, Equatable {
    /// The engine kept running; the meeting pauses itself.
    case systemWillSleep
    /// The engine restarted at the new input format.
    case deviceChanged
}
