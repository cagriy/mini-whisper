import AppKit
import SwiftUI

/// Hosts `MeetingView` in a 920×620 window (design §5.3). Closing it only hides a live
/// meeting; recording continues and *Show Meeting…* brings it back (§5.7).
@MainActor
final class MeetingWindowController: NSObject, NSWindowDelegate, MeetingWindowPresenting {
    private let window: NSWindow
    private let closed: @MainActor () -> Void

    init(model: MeetingWindowModel, actions: MeetingActions) {
        closed = actions.closed
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MeetingView(model: model, actions: actions))
        window.center()
        window.delegate = self
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        // An LSUIElement app has no menu bar, so ⌘C/⌘V in the notes need one.
        EditMenu.ensure()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func setTitle(_ title: String) {
        window.title = title
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        closed()
    }
}
