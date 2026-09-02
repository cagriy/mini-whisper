import CoreGraphics
import MWHotkeys
import Testing
@testable import MiniWhisper

@Suite struct CGEventConversionTests {
    @Test func keyDownCarriesVKAndChars() {
        #expect(
            CGEventConversion.keyEvent(type: .keyDown, keyCode: 49, flags: 0, characters: " ")
                == .keyDown(vk: 49, chars: " ")
        )
        #expect(
            CGEventConversion.keyEvent(type: .keyUp, keyCode: 49, flags: 0, characters: nil)
                == .keyUp(vk: 49)
        )
        #expect(
            CGEventConversion.keyEvent(type: .scrollWheel, keyCode: 0, flags: 0, characters: nil) == nil
        )
    }

    @Test func flagsChangedForVK54WithCmdSetIsPress() throws {
        // Right command down: the command bit plus the device-dependent right-hand bit.
        let event = CGEventConversion.keyEvent(
            type: .flagsChanged,
            keyCode: 54,
            flags: 0x10_0010,
            characters: nil
        )
        #expect(event == .flagsChanged(flags: [.command], vk: 54))

        var matcher = try HotkeyMatcher(bindings: [.pasteSubmit: HotkeyCombo.parse("cmd_r")])
        #expect(matcher.handle(try #require(event), now: 0) == [.pressed(.pasteSubmit)])
    }

    @Test func flagsChangedForVK54WithCmdClearIsRelease() throws {
        var matcher = try HotkeyMatcher(bindings: [.pasteSubmit: HotkeyCombo.parse("cmd_r")])
        let down = try #require(
            CGEventConversion.keyEvent(type: .flagsChanged, keyCode: 54, flags: 0x10_0010, characters: nil)
        )
        _ = matcher.handle(down, now: 0)

        let up = CGEventConversion.keyEvent(type: .flagsChanged, keyCode: 54, flags: 0, characters: nil)
        #expect(up == .flagsChanged(flags: [], vk: 54))
        #expect(matcher.handle(try #require(up), now: 0.1) == [.released(.pasteSubmit)])
    }

    @Test func flagsMaskToModifierFlags() {
        // Caps lock (0x10000), numeric pad (0x200000) and fn (0x800000) are not bindable.
        #expect(CGEventConversion.modifierFlags(0x91_0000) == [.command])
        #expect(
            CGEventConversion.modifierFlags(0x1E_0000) == [.shift, .control, .option, .command]
        )
        #expect(CGEventConversion.modifierFlags(0) == [])
    }
}
