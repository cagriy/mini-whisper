import AppKit
import SwiftUI

/// Hosts `HistoryView`. Like Settings, showing the window makes the app a regular
/// one so it can take focus, and it goes back to the menu bar with its last window —
/// including the hide that precedes a paste (F30).
@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let model: HistoryListModel
    private let window: NSWindow

    init(model: HistoryListModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "History"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HistoryView(model: model))
        window.center()
        window.delegate = self
    }

    func show() {
        // An LSUIElement app has no menu bar, so ⌘C/⌘V in the search field need one.
        EditMenu.ensure()
        Task { await model.reload() }
        WindowActivation.shown(window)
    }

    func hide() {
        window.orderOut(nil)
        WindowActivation.closed()
    }

    func windowWillClose(_ notification: Notification) {
        WindowActivation.closed()
    }
}
