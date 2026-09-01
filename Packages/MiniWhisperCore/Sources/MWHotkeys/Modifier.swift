/// A side-agnostic modifier. `Comparable` orders by raw value, which reproduces
/// the Python display order (`sorted(modifiers, key=str)` over `Key.alt`,
/// `Key.cmd`, `Key.ctrl`, `Key.shift`).
public enum Modifier: String, Codable, CaseIterable, Comparable, Sendable {
    case alt
    case cmd
    case ctrl
    case shift

    public var symbol: String {
        switch self {
        case .alt: "⌥"
        case .cmd: "⌘"
        case .ctrl: "⌃"
        case .shift: "⇧"
        }
    }

    public static func < (lhs: Modifier, rhs: Modifier) -> Bool { lhs.rawValue < rhs.rawValue }
}
