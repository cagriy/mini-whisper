import AppKit
import MWPaste
import MWPipeline

/// F17: the paste target and profile are resolved from the frontmost app at release.
struct NSWorkspaceFrontmostApp: FrontmostAppProviding {
    func frontmost() -> PasteTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return PasteTarget(
            pid: app.processIdentifier,
            name: app.localizedName ?? "",
            bundleID: app.bundleIdentifier
        )
    }
}

/// §5.7: a target that quit between release and paste is detected before posting.
struct RunningProcessCheck: ProcessCheck {
    func isRunning(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid) != nil
    }
}
