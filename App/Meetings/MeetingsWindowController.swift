import AppKit
import SwiftUI

/// Hosts `MeetingsListView` in a 680×480 window (design §5.3). Like History, showing it makes
/// the app a regular one so it can take focus.
@MainActor
final class MeetingsWindowController: NSObject, NSWindowDelegate {
    let model: MeetingsListModel
    private let window: NSWindow

    init(model: MeetingsListModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "Meetings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MeetingsListView(model: model))
        window.center()
        window.delegate = self
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        // An LSUIElement app has no menu bar, so ⌘C/⌘V in the search field need one.
        EditMenu.ensure()
        Task { await model.reload() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
