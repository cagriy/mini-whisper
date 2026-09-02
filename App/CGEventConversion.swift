import CoreGraphics
import MWHotkeys

/// Pure mapping from a `CGEvent`'s field values to a `KeyEvent` (design §5.4).
/// Kept free of `CGEvent` itself so the tap's translation is unit-testable.
enum CGEventConversion {
    /// The four bindable modifiers. Caps lock, fn, the numeric-pad bit and the
    /// device-dependent left/right bits are not part of a combo and are dropped;
    /// the side of a modifier comes from the virtual key, not from the flags.
    private static let bindable: ModifierFlags = [.shift, .control, .option, .command]

    static func modifierFlags(_ raw: UInt64) -> ModifierFlags {
        ModifierFlags(rawValue: raw & bindable.rawValue)
    }

    static func keyEvent(
        type: CGEventType,
        keyCode: Int64,
        flags: UInt64,
        characters: String?
    ) -> KeyEvent? {
        let virtualKey = UInt16(truncatingIfNeeded: keyCode)
        switch type {
        case .keyDown: return .keyDown(vk: virtualKey, chars: characters)
        case .keyUp: return .keyUp(vk: virtualKey)
        case .flagsChanged: return .flagsChanged(flags: modifierFlags(flags), vk: virtualKey)
        default: return nil
        }
    }
}
