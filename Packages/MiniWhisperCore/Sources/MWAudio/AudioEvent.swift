public enum AudioEvent: Sendable, Equatable {
    case live
    case deviceChanged
    case stopped
}

public enum AudioBackendEvent: Sendable, Equatable {
    case configurationChanged
    case systemWillSleep
}
