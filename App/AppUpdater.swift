import AppKit
import Sparkle

/// Sparkle's updater, started once at launch. The feed URL, the EdDSA public key
/// and the daily check cadence all come from `Info.plist`, and Sparkle owns both
/// its own preferences and its own UI, so there is nothing here but wiring.
@MainActor
enum AppUpdater {
    private static let userDriverSupport = UpdaterUserDriverSupport()
    private static var controller: SPUStandardUpdaterController?

    static func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: userDriverSupport
        )
    }

    /// Sparkle reads and writes this itself on every scheduled check, so it is the
    /// one preference that lives outside `config.json`.
    static var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    static func checkForUpdates() {
        // A user-initiated check gets no `willHandleShowingUpdate` callback when
        // there is nothing to install, so the "up to date" alert needs the policy
        // raised here instead.
        UpdaterUserDriverSupport.beginForeground()
        controller?.checkForUpdates(nil)
    }
}

/// Mini Whisper is an `LSUIElement` app sitting at `.accessory`, so Sparkle's
/// windows would otherwise open behind the frontmost app. Same activation-policy
/// dance as `AboutPanel` and the window controllers.
private final class UpdaterUserDriverSupport: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    @MainActor static func beginForeground() {
        _ = NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else { return }
        MainActor.assumeIsolated { Self.beginForeground() }
    }

    func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
    }
}

/// Adapts `AppUpdater`'s statics to the Settings seam. Every call arrives from
/// `SettingsModel`, which is `@MainActor`.
final class SparkleUpdateChecking: UpdateChecking {
    var automaticallyChecksForUpdates: Bool {
        get { MainActor.assumeIsolated { AppUpdater.automaticallyChecksForUpdates } }
        set { MainActor.assumeIsolated { AppUpdater.automaticallyChecksForUpdates = newValue } }
    }

    func checkForUpdates() {
        MainActor.assumeIsolated { AppUpdater.checkForUpdates() }
    }
}
