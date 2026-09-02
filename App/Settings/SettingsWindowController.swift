import AppKit
import MWSupport
import SwiftUI

/// Hosts `SettingsView`. Like the source, showing the window makes the app a
/// regular one so it can take focus, and closing it puts it back in the menu bar.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model: SettingsModel
    private let window: SettingsWindow

    init(model: SettingsModel) {
        self.model = model
        window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "Mini Whisper Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.center()
        window.delegate = self
        // Esc while a hotkey field is capturing restores the previous combo (F7).
        window.onCancel = { [weak model] in model?.cancelCapture() }
    }

    func show() {
        EditMenu.ensure()
        model.refreshKeys()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelCapture()
        NSApp.setActivationPolicy(.accessory)
    }
}

private final class SettingsWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// `LSUIElement` apps have no menu bar, so ⌘C/⌘V would not work in the key and
/// prompt fields. Port of `settings.py:_ensure_edit_menu`.
@MainActor
enum EditMenu {
    static func ensure() {
        let mainMenu = NSApp.mainMenu ?? {
            let menu = NSMenu()
            NSApp.mainMenu = menu
            return menu
        }()
        guard !mainMenu.items.contains(where: { $0.title == "Edit" }) else { return }

        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }

        let item = NSMenuItem()
        item.title = "Edit"
        item.submenu = editMenu
        mainMenu.addItem(item)
    }
}
