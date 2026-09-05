import AppKit
import MWConfig
import SwiftUI

/// Hosts `CorrectionView`. One instance is reused for every correction; `show(source:)`
/// replaces the model with one built from the config as it stands right now, exactly as
/// `HistoryWindowController` reuses its window (design §5.1).
@MainActor
final class CorrectionWindowController: NSObject, NSWindowDelegate {
    private let deps: CorrectionModel.Dependencies
    private let window: NSWindow
    private var model: CorrectionModel?

    init(deps: CorrectionModel.Dependencies) {
        self.deps = deps
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "Correct Dictation"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
    }

    func show(source: CorrectionSource) {
        Task {
            let model = CorrectionModel(
                source: source, config: await deps.store.load(), deps: deps
            )
            self.model = model
            window.contentView = NSHostingView(
                rootView: CorrectionView(model: model, onClose: { [weak self] in self?.hide() })
            )
            // An LSUIElement app has no menu bar, so ⌘C/⌘V in the fields need one.
            EditMenu.ensure()
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        window.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
