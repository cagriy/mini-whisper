import AppKit
import SwiftUI

/// The one meeting window, reused for whichever meeting the coordinator presents (design §5.5).
/// Closing it leaves the meeting page; a live meeting keeps recording.
@MainActor
final class MeetingWindowController: NSObject, NSWindowDelegate {
    /// The window closed: the meeting page was left.
    var onClose: @MainActor () -> Void = {}
    private let window: NSWindow
    private weak var model: MeetingWindowModel?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        super.init()

        window.title = "Meeting"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
    }

    /// Shows `model`, replacing the meeting shown before.
    func show(model: MeetingWindowModel, actions: MeetingActions) {
        if model !== self.model {
            self.model = model
            window.contentView = NSHostingView(rootView: MeetingView(model: model, actions: actions))
        }
        // An LSUIElement app has no menu bar, so ⌘C/⌘V in the notes need one.
        EditMenu.ensure()
        WindowActivation.shown(window)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        WindowActivation.closed()
        onClose()
    }
}
