import Testing
@testable import MWHotkeys

/// Ports `hotkey.py:238-378` (`_handle_press`, `_handle_release`,
/// `_tick_watchdog`, capture handlers) — F6, F7, F8.
@Suite struct HotkeyMatcherTests {

    private enum VK {
        static let a: UInt16 = 0
        static let space: UInt16 = 49
        static let escape: UInt16 = 53
        static let cmdRight: UInt16 = 54
        static let cmdLeft: UInt16 = 55
        static let shiftLeft: UInt16 = 56
    }

    /// The F8 defaults: `paste` = `shift+cmd_r`, `paste_submit` = `cmd_r`.
    private func makeDefaultMatcher() throws -> HotkeyMatcher {
        try HotkeyMatcher(bindings: [
            .paste: HotkeyCombo.parse("shift+cmd_r"),
            .pasteSubmit: HotkeyCombo.parse("cmd_r"),
        ])
    }

    private func makeMatcher(_ bindings: [BindingName: String]) throws -> HotkeyMatcher {
        HotkeyMatcher(bindings: try bindings.mapValues { try HotkeyCombo.parse($0) })
    }

    // MARK: - matching

    @Test func modifierTriggerFiresOnExactSet() throws {
        var matcher = try makeDefaultMatcher()
        #expect(matcher.handle(.flagsChanged(flags: [.shift], vk: VK.shiftLeft), now: 0) == [])
        #expect(
            matcher.handle(.flagsChanged(flags: [.shift, .command], vk: VK.cmdRight), now: 0)
                == [.pressed(.paste)]
        )
        #expect(matcher.needsWatchdog)
    }

    @Test func modifierTriggerDoesNotFireOnSuperset() throws {
        var matcher = try makeMatcher([.pasteSubmit: "cmd_r"])
        _ = matcher.handle(.flagsChanged(flags: [.shift], vk: VK.shiftLeft), now: 0)
        #expect(matcher.handle(.flagsChanged(flags: [.shift, .command], vk: VK.cmdRight), now: 0) == [])

        var alone = try makeMatcher([.pasteSubmit: "cmd_r"])
        #expect(
            alone.handle(.flagsChanged(flags: [.command], vk: VK.cmdRight), now: 0)
                == [.pressed(.pasteSubmit)]
        )
    }

    @Test func keyTriggerFiresOnSuperset() throws {
        var matcher = try makeMatcher([.paste: "cmd+space"])
        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdLeft), now: 0)
        _ = matcher.handle(.flagsChanged(flags: [.command, .shift], vk: VK.shiftLeft), now: 0)
        #expect(matcher.handle(.keyDown(vk: VK.space, chars: " "), now: 0) == [.pressed(.paste)])
    }

    // MARK: - release

    @Test func releaseOnTriggerUp() throws {
        var matcher = try makeMatcher([.paste: "cmd+space"])
        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdLeft), now: 0)
        _ = matcher.handle(.keyDown(vk: VK.space, chars: " "), now: 0)
        #expect(matcher.handle(.keyUp(vk: VK.space), now: 0) == [.released(.paste)])
        #expect(matcher.needsWatchdog == false)
    }

    @Test func releaseOnBindingModifierUp() throws {
        var matcher = try makeMatcher([.paste: "cmd+space"])
        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdLeft), now: 0)
        _ = matcher.handle(.keyDown(vk: VK.space, chars: " "), now: 0)
        #expect(matcher.handle(.flagsChanged(flags: [], vk: VK.cmdLeft), now: 0) == [.released(.paste)])
    }

    @Test func releaseOnModifierTriggerUp() throws {
        var matcher = try makeDefaultMatcher()
        _ = matcher.handle(.flagsChanged(flags: [.shift], vk: VK.shiftLeft), now: 0)
        _ = matcher.handle(.flagsChanged(flags: [.shift, .command], vk: VK.cmdRight), now: 0)
        #expect(
            matcher.handle(.flagsChanged(flags: [.shift], vk: VK.cmdRight), now: 0)
                == [.released(.paste)]
        )
    }

    /// A missed key-up leaves a binding active with its modifiers gone; the next
    /// unrelated modifier release reconciles and deactivates it.
    @Test func safetyNetReleasesWhenModifiersDropped() throws {
        var matcher = try makeMatcher([.paste: "cmd+space"])
        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdLeft), now: 0)
        _ = matcher.handle(.flagsChanged(flags: [.command, .shift], vk: VK.shiftLeft), now: 0)
        #expect(matcher.handle(.keyDown(vk: VK.space, chars: " "), now: 0) == [.pressed(.paste)])
        // Shift up, and the OS reports cmd gone too — its key-up never arrived.
        #expect(matcher.handle(.flagsChanged(flags: [], vk: VK.shiftLeft), now: 0) == [.released(.paste)])
    }

    // MARK: - watchdog

    @Test func watchdogReleasesKeyTriggerWhenOSFlagsDrop() throws {
        var matcher = try makeMatcher([.paste: "cmd+space"])
        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdLeft), now: 0)
        _ = matcher.handle(.keyDown(vk: VK.space, chars: " "), now: 0)
        #expect(matcher.watchdogTick(osFlags: []) == [.released(.paste)])
        #expect(matcher.needsWatchdog == false)
    }

    /// Design fix over `hotkey.py:286`, which excluded modifier triggers.
    @Test func watchdogReleasesModifierTriggerWhenOSFlagsDrop() throws {
        var matcher = try makeDefaultMatcher()
        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdRight), now: 0)
        #expect(matcher.watchdogTick(osFlags: []) == [.released(.pasteSubmit)])
    }

    @Test func watchdogNoopWhileHeld() throws {
        var matcher = try makeDefaultMatcher()
        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdRight), now: 0)
        #expect(matcher.watchdogTick(osFlags: [.command]) == [])
        #expect(matcher.needsWatchdog)
    }

    // MARK: - capture mode

    @Test func capturePressNonModifierEndsCapture() throws {
        var matcher = try makeDefaultMatcher()
        matcher.beginCapture()
        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdLeft), now: 0)
        #expect(
            matcher.handle(.keyDown(vk: VK.a, chars: "a"), now: 0)
                == [.captured(HotkeyCombo(modifiers: [.cmd], trigger: .char("a", vk: 0)))]
        )
        #expect(matcher.isCapturing == false)
    }

    @Test func captureReleasingModifierYieldsModifierTrigger() throws {
        var matcher = try makeDefaultMatcher()
        matcher.beginCapture()
        _ = matcher.handle(.flagsChanged(flags: [.shift], vk: VK.shiftLeft), now: 0)
        _ = matcher.handle(.flagsChanged(flags: [.shift, .command], vk: VK.cmdRight), now: 0)
        let expected = try HotkeyCombo.parse("shift+cmd_r")
        #expect(
            matcher.handle(.flagsChanged(flags: [.shift], vk: VK.cmdRight), now: 0)
                == [.captured(expected)]
        )
        #expect(matcher.isCapturing == false)
    }

    @Test func captureBareModifierTriggerYieldsCombo() throws {
        var matcher = try makeDefaultMatcher()
        matcher.beginCapture()
        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdRight), now: 0)
        let expected = try HotkeyCombo.parse("cmd_r")
        #expect(
            matcher.handle(.flagsChanged(flags: [], vk: VK.cmdRight), now: 0)
                == [.captured(expected)]
        )
    }

    @Test func captureBareKeyRejectedAndReenters() throws {
        var matcher = try makeDefaultMatcher()
        matcher.beginCapture()
        #expect(matcher.handle(.keyDown(vk: VK.a, chars: "a"), now: 0) == [.captureRejected])
        #expect(matcher.isCapturing)
        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdLeft), now: 0)
        #expect(
            matcher.handle(.keyDown(vk: VK.a, chars: "a"), now: 0)
                == [.captured(HotkeyCombo(modifiers: [.cmd], trigger: .char("a", vk: 0)))]
        )
    }

    /// Only right-hand modifiers are expressible as triggers (F5), so releasing
    /// a left one rejects rather than building an unparseable combo.
    @Test func captureLeftModifierReleaseRejectedAndReenters() throws {
        var matcher = try makeDefaultMatcher()
        matcher.beginCapture()
        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdLeft), now: 0)
        #expect(matcher.handle(.flagsChanged(flags: [], vk: VK.cmdLeft), now: 0) == [.captureRejected])
        #expect(matcher.isCapturing)
    }

    @Test func captureEscCancels() throws {
        var matcher = try makeDefaultMatcher()
        matcher.beginCapture()
        #expect(matcher.handle(.keyDown(vk: VK.escape, chars: "\u{1b}"), now: 0) == [])
        #expect(matcher.isCapturing == false)
    }

    @Test func captureIgnoresBindings() throws {
        var matcher = try makeDefaultMatcher()
        matcher.beginCapture()
        #expect(matcher.handle(.flagsChanged(flags: [.shift], vk: VK.shiftLeft), now: 0) == [])
        #expect(matcher.handle(.flagsChanged(flags: [.shift, .command], vk: VK.cmdRight), now: 0) == [])
        #expect(matcher.needsWatchdog == false)
    }

    @Test func cancelCaptureRestoresNormalMatching() throws {
        var matcher = try makeDefaultMatcher()
        matcher.beginCapture()
        matcher.cancelCapture()
        #expect(matcher.isCapturing == false)
        _ = matcher.handle(.flagsChanged(flags: [.shift], vk: VK.shiftLeft), now: 0)
        #expect(
            matcher.handle(.flagsChanged(flags: [.shift, .command], vk: VK.cmdRight), now: 0)
                == [.pressed(.paste)]
        )
    }

    // MARK: - rebinding

    @Test func updateBindingResetsState() throws {
        var matcher = try makeDefaultMatcher()
        _ = matcher.handle(.flagsChanged(flags: [.shift], vk: VK.shiftLeft), now: 0)
        #expect(
            matcher.handle(.flagsChanged(flags: [.shift, .command], vk: VK.cmdRight), now: 0)
                == [.pressed(.paste)]
        )

        let rebound = try HotkeyCombo.parse("cmd+space")
        matcher.update(binding: .paste, combo: rebound)
        #expect(matcher.needsWatchdog == false)
        #expect(matcher.handle(.flagsChanged(flags: [.shift], vk: VK.cmdRight), now: 0) == [])

        _ = matcher.handle(.flagsChanged(flags: [.command], vk: VK.cmdLeft), now: 0)
        #expect(matcher.handle(.keyDown(vk: VK.space, chars: " "), now: 0) == [.pressed(.paste)])
    }

    // MARK: - event decoding

    @Test func modifierFlagMasksMatchDesign() {
        #expect(ModifierFlags.shift.rawValue == 0x20000)
        #expect(ModifierFlags.control.rawValue == 0x40000)
        #expect(ModifierFlags.command.rawValue == 0x100000)
        #expect(ModifierFlags.option.rawValue == 0x80000)
        #expect(ModifierFlags([.alt, .cmd]) == [.option, .command])
        #expect(ModifierFlags([.option, .shift]).modifiers == [.alt, .shift])
    }
}
