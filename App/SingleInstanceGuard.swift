import AppKit
import MWSupport

/// F36: a second copy activates the running one and exits before any window exists.
enum SingleInstanceGuard {
    /// Returns `false` when another instance already owns the bundle ID.
    static func claim(bundleID: String = Bundle.main.bundleIdentifier ?? "") -> Bool {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing = others.first else { return true }
        Log.ui.info("Another instance is running (pid \(existing.processIdentifier)); activating it")
        existing.activate(options: [.activateAllWindows])
        return false
    }
}
