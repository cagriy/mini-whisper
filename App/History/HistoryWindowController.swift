import AppKit
import MWPipeline
import SwiftUI

/// Hosts `HistoryView`. Like Settings, showing the window makes the app a regular
/// one so it can take focus, and it goes back to the menu bar when the window goes
/// away — including the hide that precedes a paste (F30).
@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let model: HistoryListModel
    private let frontmost: any FrontmostAppProviding
    private let window: NSWindow

    init(model: HistoryListModel, frontmost: any FrontmostAppProviding) {
        self.model = model
        self.frontmost = frontmost
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
        // F30: the paste target is whatever was frontmost before this window took focus.
        model.previousApp = frontmost.frontmost().flatMap {
            $0.pid == ProcessInfo.processInfo.processIdentifier ? nil : $0
        }
        Task { await model.reload() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
