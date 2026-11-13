import AppKit
import MWPipeline
import Observation

/// The app last frontmost other than Mini Whisper: where a dictation is pasted from any of
/// its windows (design §5.13).
@MainActor
@Observable
final class FrontAppTracker {
    private(set) var previousApp: PasteTarget?

    init(
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        frontmost: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        previousApp = Self.target(frontmost, ownPID: ownPID)
        // Never removed: the tracker lives as long as the app.
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let target = Self.target(app, ownPID: ownPID) else { return }
            MainActor.assumeIsolated { self?.previousApp = target }
        }
    }

    private nonisolated static func target(_ app: NSRunningApplication?, ownPID: pid_t) -> PasteTarget? {
        guard let app, app.processIdentifier != ownPID else { return nil }
        return PasteTarget(app)
    }
}
