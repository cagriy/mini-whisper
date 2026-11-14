import AppKit
import MWConfig
import MWSupport
import SwiftUI

/// The one main window (design §5.8, R1, R6): hidden rather than closed, placed from
/// `config.json` on its first show, and its frame stored again when it hides.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    let model: MainWindowModel
    private let window: MainWindow
    private let store: ConfigStore
    /// The frame `config.json` holds, as far as this window knows.
    private var stored: WindowFrame?
    private var placed = false

    init(model: MainWindowModel, store: ConfigStore, savedFrame: WindowFrame?) {
        self.model = model
        self.store = store
        stored = savedFrame
        window = MainWindow(
            contentRect: CGRect(origin: .zero, size: WindowFramePolicy.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()

        window.title = "Mini Whisper"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = WindowFramePolicy.minimumSize
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MainView(model: model))
        // The window sets the size; the content never resizes it.
        host.sizingOptions = []
        window.contentView = host
        window.delegate = self
        // Esc while a hotkey field is capturing restores the previous combo (F7).
        window.onCancel = { [weak model] in model?.settings.cancelCapture() }
    }

    func show(_ destination: MainNavigationModel.Destination) {
        model.navigation.go(destination)
        bringForward(destination)
    }

    /// The meeting page with `meeting` on it (design §5.5 `present`).
    func showMeeting(_ meeting: MeetingWindowModel, actions: MeetingActions) {
        model.showMeeting(meeting, actions: actions)
        bringForward(.meeting)
    }

    private func bringForward(_ destination: MainNavigationModel.Destination) {
        // An LSUIElement app has no menu bar, so ⌘C/⌘V in the fields need one.
        EditMenu.ensure()
        if !placed { place() }
        Log.ui.info("main window shown: \(destination)")
        WindowActivation.shown(window)
    }

    /// Orders the window out and stores its frame; quitting waits for the write. A hotkey
    /// capture under way gives way to the previous combo.
    @discardableResult
    func hide() -> Task<Void, Never> {
        model.settings.cancelCapture()
        let saving = saveFrame()
        if window.isVisible || window.isMiniaturized {
            window.orderOut(nil)
            Log.ui.info("main window hidden")
        }
        WindowActivation.closed()
        return saving
    }

    func windowWillClose(_ notification: Notification) {
        model.settings.cancelCapture()
        saveFrame()
        Log.ui.info("main window hidden")
        WindowActivation.closed()
    }

    private func place() {
        placed = true
        let screens = WindowFramePolicy.Screens(
            visible: NSScreen.screens.map(\.visibleFrame), main: NSScreen.main?.visibleFrame
        )
        let frame = WindowFramePolicy.frame(saved: stored, screens: screens)
        let restored = stored != nil && frame != WindowFramePolicy.frame(saved: nil, screens: screens)
        Log.ui.info("main window frame \(restored ? "restored" : "defaulted")")
        window.setFrame(frame, display: false)
    }

    /// Only a frame that differs from the stored one is written, and never during a resize.
    @discardableResult
    private func saveFrame() -> Task<Void, Never> {
        guard placed else { return Task {} }
        let frame = WindowFrame(window.frame)
        guard frame != stored else { return Task {} }
        let previous = stored
        stored = frame
        let store = store
        return Task { [weak self] in
            do {
                try await store.update { @Sendable in $0.mainWindowFrame = frame }
            } catch {
                Log.ui.warning("main window frame not saved: \(AnyError(error).description)")
                // Tried again at the next hide.
                if self?.stored == frame { self?.stored = previous }
            }
        }
    }
}

private final class MainWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private extension WindowFrame {
    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }
}
