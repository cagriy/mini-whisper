import AppKit
import MWSupport

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sounds = SoundPlayer()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The AppTests bundle is hosted by this app; starting normally there would
        // touch the user's config, Keychain and input devices.
        guard !LaunchArguments.isRunningTests else { return }

        guard SingleInstanceGuard.claim() else { exit(0) }
        configureLogging()

        let permitted = PermissionMonitor.allGranted
        statusItem = StatusItemController(
            sounds: sounds,
            onHistory: { Log.ui.info("History window arrives in Stage 29") },
            onSettings: { Log.ui.info("Settings window arrives in Stage 27") },
            onQuit: { [weak self] in self?.quit() }
        )

        if permitted {
            Log.ui.info("Permissions granted; dictation wiring arrives in Stage 24")
        } else {
            Log.ui.info(
                "Permissions missing (microphone \(PermissionMonitor.microphoneGranted),"
                    + " accessibility \(PermissionMonitor.accessibilityGranted));"
                    + " onboarding arrives in Stage 26"
            )
        }
    }

    private func configureLogging() {
        let arguments = LaunchArguments()
        Log.configure(
            debug: arguments.debug,
            sinks: arguments.debug ? [FileLogSink(url: LaunchArguments.debugLogURL)] : []
        )
        Log.ui.info("Mini Whisper launched (debug: \(arguments.debug))")
    }

    private func quit() {
        NSApp.terminate(nil)
    }
}
