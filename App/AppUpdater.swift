import AppKit
import MWConfig
import Sparkle

/// Sparkle's updater, started once at launch. The feed URL, the EdDSA public key
/// and the daily check cadence all come from `Info.plist`, and Sparkle owns both
/// its own preferences and its own UI, so there is nothing here but wiring. The
/// update channel is the one updater setting that comes from `config.json`.
@MainActor
enum AppUpdater {
    private static let userDriverSupport = UpdaterUserDriverSupport()
    /// Sparkle holds its delegates weakly; unowned, this would vanish and every
    /// check would fall back to the default channel without a word.
    private static let channelDelegate = UpdaterChannelDelegate()
    private static var controller: SPUStandardUpdaterController?

    /// Set by `AppDelegate.apply` from `config.json`; Sparkle reads it at every check.
    static var channel: UpdateChannel = .release

    static func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: channelDelegate,
            userDriverDelegate: userDriverSupport
        )
    }

    /// R6: checks again shortly, so a newly allowed beta is found without waiting a day.
    static func channelChanged() {
        controller?.updater.resetUpdateCycleAfterShortDelay()
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
        WindowActivation.foreground()
        controller?.checkForUpdates(nil)
    }
}

/// R5: Sparkle asks while filtering each downloaded appcast, Check Now included.
private final class UpdaterChannelDelegate: NSObject, SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UpdateChannelPolicy.sparkleChannels(for: AppUpdater.channel)
    }
}

/// Mini Whisper is an `LSUIElement` app sitting at `.accessory`, so Sparkle's
/// windows would otherwise open behind the frontmost app.
private final class UpdaterUserDriverSupport: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else { return }
        MainActor.assumeIsolated { WindowActivation.foreground() }
    }

    /// Sparkle closes its windows after this returns, which the deferred check allows for.
    func standardUserDriverWillFinishUpdateSession() {
        WindowActivation.closed()
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
