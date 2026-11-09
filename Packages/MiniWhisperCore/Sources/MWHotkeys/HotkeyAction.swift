/// F8's two dictation bindings (`hotkey`, `submit_hotkey`) and the meeting toggle
/// (`meeting_hotkey`).
public enum BindingName: String, CaseIterable, Hashable, Sendable {
    case paste
    case pasteSubmit = "paste_submit"
    case meeting
}

public enum HotkeyAction: Hashable, Sendable {
    case pressed(BindingName)
    case released(BindingName)
    case captured(HotkeyCombo)
    case captureRejected
}
