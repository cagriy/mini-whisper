import Foundation
import Testing
@testable import MWHotkeys

/// Ports the 13 cases of `../mini-whisper/tests/test_hotkey.py` plus the
/// display-order and virtual-key-table checks the Python suite left implicit.
@Suite struct HotkeyComboTests {

    // MARK: - parse

    @Test func parsesModifierPlusKey() throws {
        let combo = try HotkeyCombo.parse("cmd+shift+space")
        #expect(combo.modifiers == [.cmd, .shift])
        #expect(combo.trigger == .key(.space))
        #expect(combo.isModifierTrigger == false)
        #expect(combo.canonicalTrigger == nil)
    }

    @Test func parsesModifierTrigger() throws {
        let combo = try HotkeyCombo.parse("shift+cmd_r")
        #expect(combo.modifiers == [.shift])
        #expect(combo.trigger == .modifier(.cmdRight))
        #expect(combo.isModifierTrigger)
        #expect(combo.canonicalTrigger == .cmd)
    }

    @Test func parsesSingleModifierTrigger() throws {
        let combo = try HotkeyCombo.parse("cmd_r")
        #expect(combo.modifiers.isEmpty)
        #expect(combo.trigger == .modifier(.cmdRight))
        #expect(combo.isModifierTrigger)
    }

    @Test func parsesSingleCharKey() throws {
        let combo = try HotkeyCombo.parse("cmd+a")
        #expect(combo.modifiers == [.cmd])
        #expect(combo.trigger == .char("a", vk: 0))
        #expect(combo.isModifierTrigger == false)
    }

    @Test func parsesTab() throws {
        let combo = try HotkeyCombo.parse("ctrl+tab")
        #expect(combo.modifiers == [.ctrl])
        #expect(combo.trigger == .key(.tab))
    }

    @Test func noTriggerThrows() throws {
        let error = try #require(throws: HotkeyParseError.self) {
            try HotkeyCombo.parse("cmd+shift")
        }
        #expect(error == .noTrigger("cmd+shift"))
        #expect(error.errorDescription == "No trigger key found in combo: cmd+shift")
    }

    @Test func unknownKeyThrows() throws {
        let error = try #require(throws: HotkeyParseError.self) {
            try HotkeyCombo.parse("cmd+foo")
        }
        #expect(error == .unknownKey("foo"))
        #expect(error.errorDescription == "Unknown key: foo")
    }

    @Test func emptyThrows() throws {
        let error = try #require(throws: HotkeyParseError.self) {
            try HotkeyCombo.parse("")
        }
        #expect(error == .unknownKey(""))
    }

    @Test func multipleTriggersThrows() throws {
        let error = try #require(throws: HotkeyParseError.self) {
            try HotkeyCombo.parse("cmd_r+shift_r")
        }
        #expect(error == .multipleTriggers("cmd_r+shift_r"))
        #expect(error.errorDescription == "Multiple trigger keys in combo: cmd_r+shift_r")
    }

    // MARK: - configString

    @Test(arguments: ["shift+cmd_r", "cmd_r", "cmd+space", "cmd+shift+space", "ctrl+tab"])
    func configStringRoundTrips(_ combo: String) throws {
        let parsed = try HotkeyCombo.parse(combo)
        #expect(parsed.configString == combo)
        #expect(try HotkeyCombo.parse(parsed.configString) == parsed)
    }

    // MARK: - displayString

    @Test func displayStringSymbols() throws {
        #expect(try HotkeyCombo.parse("cmd+shift+space").displayString == "⌘⇧Space")
    }

    @Test func displayModifierTrigger() throws {
        #expect(try HotkeyCombo.parse("shift+cmd_r").displayString == "⇧Right ⌘")
    }

    @Test func displaySingleModifierTrigger() throws {
        #expect(try HotkeyCombo.parse("cmd_r").displayString == "Right ⌘")
    }

    @Test func displayCharKey() throws {
        #expect(try HotkeyCombo.parse("cmd+a").displayString == "⌘A")
    }

    /// Python sorts the modifier set by `str(Key)`: alt, cmd, ctrl, shift.
    @Test func modifierDisplayOrderMatchesPython() throws {
        let combo = try HotkeyCombo.parse("shift+ctrl+cmd+alt+space")
        #expect(combo.displayString == "⌥⌘⌃⇧Space")
        #expect(combo.configString == "alt+cmd+ctrl+shift+space")
    }

    // MARK: - virtual key table

    @Test func vkTableMatchesPython() {
        #expect(VirtualKeyTable.character(for: 0) == "a")
        #expect(VirtualKeyTable.character(for: 9) == "v")
        #expect(VirtualKeyTable.character(for: 50) == "`")
        #expect(VirtualKeyTable.character(for: 49) == nil)
        #expect(VirtualKeyTable.virtualKey(for: "v") == 9)
        #expect(VirtualKeyTable.virtualKey(for: "é") == nil)
    }

    @Test func sidedModifierVirtualKeysMatchDesign() {
        #expect(SidedModifier.cmdRight.virtualKey == 54)
        #expect(SidedModifier.shiftRight.virtualKey == 60)
        #expect(SidedModifier.altRight.virtualKey == 61)
        #expect(SidedModifier.ctrlRight.virtualKey == 62)
        #expect(SidedModifier.allCases.map(\.canonical) == [.cmd, .shift, .alt, .ctrl])
    }

    // MARK: - Codable

    @Test func codesAsItsConfigString() throws {
        let combo = try HotkeyCombo.parse("shift+cmd_r")
        let data = try JSONEncoder().encode([combo])
        #expect(String(decoding: data, as: UTF8.self) == "[\"shift+cmd_r\"]")
        #expect(try JSONDecoder().decode([HotkeyCombo].self, from: data) == [combo])
    }
}
