/// A raw event from the CGEventTap, before any matching (design §5.4).
public enum KeyEvent: Hashable, Sendable {
    case keyDown(vk: UInt16, chars: String?)
    case keyUp(vk: UInt16)
    case flagsChanged(flags: ModifierFlags, vk: UInt16)

    static let escapeVirtualKey: UInt16 = 53

    /// Modifier virtual keys, both sides. A right-hand key also carries its
    /// `SidedModifier` identity, which is what a modifier-trigger matches on.
    static let modifierVirtualKeys: [UInt16: Modifier] = [
        54: .cmd, 55: .cmd, 56: .shift, 58: .alt, 59: .ctrl, 60: .shift, 61: .alt, 62: .ctrl,
    ]
}

/// A `KeyEvent`'s key resolved to what the matcher compares against — the
/// Swift equivalent of `hotkey.py`'s `_to_canonical`.
enum ResolvedKey: Hashable {
    case modifier(Modifier, sided: SidedModifier?)
    case trigger(Trigger)
    case escape
    case unknown

    init(vk: UInt16, chars: String?) {
        if let named = NamedKey(virtualKey: vk) {
            self = .trigger(.key(named))
        } else if vk == KeyEvent.escapeVirtualKey {
            self = .escape
        } else if let modifier = KeyEvent.modifierVirtualKeys[vk] {
            self = .modifier(modifier, sided: SidedModifier(virtualKey: vk))
        } else if let character = VirtualKeyTable.character(for: vk) {
            self = .trigger(.char(character, vk: vk))
        } else if let character = chars?.lowercased().first, chars?.count == 1 {
            self = .trigger(.char(character, vk: VirtualKeyTable.virtualKey(for: character)))
        } else {
            self = .unknown
        }
    }
}
