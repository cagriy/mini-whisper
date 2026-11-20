import AppKit
import SwiftUI

/// Credits (design §5, R26): a fixed 460 by 440 small window, opened from About, whose content scrolls.
@MainActor
final class CreditsWindowController: NSObject, NSWindowDelegate {
    let window = NSWindow.small(title: "Credits", size: CGSize(width: 460, height: 440))

    override init() {
        super.init()
        window.host(CreditsView())
        window.delegate = self
    }

    func show() {
        WindowActivation.shown(window)
    }

    func windowWillClose(_ notification: Notification) {
        WindowActivation.closed()
    }
}
