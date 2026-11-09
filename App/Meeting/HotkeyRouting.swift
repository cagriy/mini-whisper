import MWHotkeys

/// Where a hotkey action goes (design §5.3 `onAction`, R19): the meeting binding toggles the
/// meeting, and while a meeting holds the microphone a dictation press only shows a notice.
enum HotkeyRouting {
    enum Route: Equatable {
        case dictation(HotkeyAction)
        case meeting
        case notice(String)
        case settings(HotkeyAction)
        case ignore
    }

    static let dictationLocked = "Dictation is off while a meeting is recording"

    static func route(_ action: HotkeyAction, meetingActive: Bool) -> Route {
        switch action {
        case .pressed(.meeting): .meeting
        case .released(.meeting): .ignore
        case .pressed: meetingActive ? .notice(dictationLocked) : .dictation(action)
        case .released: meetingActive ? .ignore : .dictation(action)
        case .captured, .captureRejected: .settings(action)
        }
    }
}
