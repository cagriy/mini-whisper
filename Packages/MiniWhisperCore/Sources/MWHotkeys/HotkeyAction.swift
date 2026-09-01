/// The two bindings of F8: config keys `hotkey` and `submit_hotkey`.
public enum BindingName: String, CaseIterable, Hashable, Sendable {
    case paste
    case pasteSubmit = "paste_submit"
}

public enum HotkeyAction: Hashable, Sendable {
    case pressed(BindingName)
    case released(BindingName)
    case captured(HotkeyCombo)
    case captureRejected
}
