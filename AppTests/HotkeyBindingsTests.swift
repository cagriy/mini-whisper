import MWConfig
import MWHotkeys
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct HotkeyBindingsTests {
    @Test func meetingBindingComesFromConfig() throws {
        var config = Config()
        config.meetingHotkey = "ctrl+alt+cmd+j"

        let bindings = AppDelegate.bindings(from: config)

        #expect(bindings[.meeting] == (try HotkeyCombo.parse("ctrl+alt+cmd+j")))
        #expect(bindings[.paste] == (try HotkeyCombo.parse("shift+cmd_r")))
        #expect(bindings[.pasteSubmit] == (try HotkeyCombo.parse("cmd_r")))
    }

    @Test func unparsableMeetingComboFallsBackToTheDefault() throws {
        var config = Config()
        config.meetingHotkey = "ctrl+bogus"

        #expect(AppDelegate.bindings(from: config)[.meeting] == (try HotkeyCombo.parse("ctrl+alt+cmd+m")))
    }

    @Test func meetingComboEqualToADictationComboFallsBackToTheDefault() throws {
        var config = Config()
        config.meetingHotkey = "shift+cmd_r"

        let bindings = AppDelegate.bindings(from: config)

        #expect(bindings[.meeting] == (try HotkeyCombo.parse("ctrl+alt+cmd+m")))
        #expect(bindings[.paste] == (try HotkeyCombo.parse("shift+cmd_r")))
    }
}
