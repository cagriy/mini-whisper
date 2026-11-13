import AppKit

/// The Dock icon follows the titled windows (design §5.8, R7): there from the first one
/// shown until the last one goes.
@MainActor
enum WindowActivation {
    /// For an alert, or a window another framework shows: nothing here to order front.
    static func foreground() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func shown(_ window: NSWindow) {
        foreground()
        window.makeKeyAndOrderFront(nil)
    }

    /// A window closed or hid. Checked on the next main-queue turn: inside `windowWillClose`
    /// the closing window is still visible.
    nonisolated static func closed() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard !NSApp.windows.contains(where: keepsDockIcon) else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// A minimised window counts, or restoring it would show a window without the icon.
    private static func keepsDockIcon(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && (window.isVisible || window.isMiniaturized)
    }
}
