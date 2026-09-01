/// A named non-character trigger key (`_KEY_MAP` in `hotkey.py`).
public enum NamedKey: String, Codable, CaseIterable, Sendable {
    case space
    case tab
    case enter

    public var displayName: String { rawValue.capitalized }

    public var virtualKey: UInt16 {
        switch self {
        case .space: 49
        case .tab: 48
        case .enter: 36
        }
    }

    public init?(virtualKey: UInt16) {
        guard let match = Self.allCases.first(where: { $0.virtualKey == virtualKey }) else { return nil }
        self = match
    }
}

/// A right-hand modifier usable as a trigger (`_MODIFIER_TRIGGER_MAP`), carrying
/// its macOS virtual key code (design §5.4).
public enum SidedModifier: String, Codable, CaseIterable, Sendable {
    case cmdRight = "cmd_r"
    case shiftRight = "shift_r"
    case altRight = "alt_r"
    case ctrlRight = "ctrl_r"

    public var virtualKey: UInt16 {
        switch self {
        case .cmdRight: 54
        case .shiftRight: 60
        case .altRight: 61
        case .ctrlRight: 62
        }
    }

    /// The side-agnostic modifier this key also contributes to the held set
    /// (`_TRIGGER_TO_CANONICAL`).
    public var canonical: Modifier {
        switch self {
        case .cmdRight: .cmd
        case .shiftRight: .shift
        case .altRight: .alt
        case .ctrlRight: .ctrl
        }
    }

    public var displayName: String { "Right \(canonical.symbol)" }

    public init?(virtualKey: UInt16) {
        guard let match = Self.allCases.first(where: { $0.virtualKey == virtualKey }) else { return nil }
        self = match
    }
}

public enum Trigger: Hashable, Sendable {
    case key(NamedKey)
    case char(Character, vk: UInt16?)
    case modifier(SidedModifier)
}
