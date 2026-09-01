import Foundation

public enum HotkeyParseError: Error, Equatable, LocalizedError {
    case unknownKey(String)
    case noTrigger(String)
    case multipleTriggers(String)

    public var errorDescription: String? {
        switch self {
        case .unknownKey(let part): "Unknown key: \(part)"
        case .noTrigger(let combo): "No trigger key found in combo: \(combo)"
        case .multipleTriggers(let combo): "Multiple trigger keys in combo: \(combo)"
        }
    }
}

/// A hotkey combo: a set of modifiers plus exactly one trigger.
///
/// Grammar, config strings and display strings are ports of `hotkey.py`'s
/// `parse_hotkey`, `build_combo_string` and `format_hotkey` (design F5).
/// Coded as its config string so it round-trips through `config.json`.
public struct HotkeyCombo: Hashable, Sendable, Codable {
    public let modifiers: Set<Modifier>
    public let trigger: Trigger

    public init(modifiers: Set<Modifier> = [], trigger: Trigger) {
        self.modifiers = modifiers
        self.trigger = trigger
    }

    public static func parse(_ combo: String) throws -> HotkeyCombo {
        var modifiers: Set<Modifier> = []
        var trigger: Trigger?

        for part in combo.split(separator: "+", omittingEmptySubsequences: false)
            .map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            let parsed: Trigger
            if let sided = SidedModifier(rawValue: part) {
                parsed = .modifier(sided)
            } else if let modifier = Modifier(rawValue: part) {
                modifiers.insert(modifier)
                continue
            } else if let named = NamedKey(rawValue: part) {
                parsed = .key(named)
            } else if part.count == 1, let character = part.first {
                parsed = .char(character, vk: VirtualKeyTable.virtualKey(for: character))
            } else {
                throw HotkeyParseError.unknownKey(part)
            }
            guard trigger == nil else { throw HotkeyParseError.multipleTriggers(combo) }
            trigger = parsed
        }

        guard let trigger else { throw HotkeyParseError.noTrigger(combo) }
        return HotkeyCombo(modifiers: modifiers, trigger: trigger)
    }

    /// The `config.json` form, e.g. `shift+cmd_r`.
    public var configString: String {
        let triggerPart: String
        switch trigger {
        case .key(let named): triggerPart = named.rawValue
        case .char(let character, _): triggerPart = String(character)
        case .modifier(let sided): triggerPart = sided.rawValue
        }
        return (modifiers.sorted().map(\.rawValue) + [triggerPart]).joined(separator: "+")
    }

    /// The menu/Settings form, e.g. `⌘⇧Space` or `⇧Right ⌘`.
    public var displayString: String {
        let triggerPart: String
        switch trigger {
        case .key(let named): triggerPart = named.displayName
        case .char(let character, _): triggerPart = String(character).uppercased()
        case .modifier(let sided): triggerPart = sided.displayName
        }
        return (modifiers.sorted().map(\.symbol) + [triggerPart]).joined()
    }

    public var isModifierTrigger: Bool {
        if case .modifier = trigger { true } else { false }
    }

    /// The side-agnostic modifier a modifier-trigger also holds down.
    public var canonicalTrigger: Modifier? {
        if case .modifier(let sided) = trigger { sided.canonical } else { nil }
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = try HotkeyCombo.parse(raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(configString)
    }
}
