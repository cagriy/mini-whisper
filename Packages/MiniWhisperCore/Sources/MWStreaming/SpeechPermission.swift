/// Speech Recognition permission as the pipeline reasons about it (F23), a port of
/// `ensure_authorized` in `../mini-whisper/src/mini_whisper/streaming/on_device.py`.
public enum SpeechPermission: Sendable, Equatable {
    case undetermined
    case denied
    case authorized

    /// The current status, triggering the system prompt when not yet determined.
    public static func ensureAuthorized(api: any SpeechRecognitionAPI) -> SpeechPermission {
        let permission: SpeechPermission
        switch api.authorizationStatus {
        case .notDetermined: permission = .undetermined
        case .denied, .restricted: permission = .denied
        case .authorized: permission = .authorized
        }
        if permission == .undetermined { api.requestAuthorization() }
        return permission
    }
}
