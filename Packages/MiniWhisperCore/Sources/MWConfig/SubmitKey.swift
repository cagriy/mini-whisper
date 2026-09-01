public enum SubmitKey: String, Codable, CaseIterable, Sendable {
    case enter
    case shiftEnter = "shift_enter"
    case cmdEnter = "cmd_enter"
}
