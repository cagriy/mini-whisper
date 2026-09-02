import AppKit
import MWStreaming
import MWSupport

/// F32's first-launch dialog: the rule that decides whether to ask, and what each
/// answer does. The `NSAlert` itself is `ask()`, so the rule stays host-tested.
struct SpeechModelPrompt: Sendable {
    enum Choice: Sendable {
        case download
        case notNow
    }

    private let install: @Sendable () async throws -> Void
    private let markPrompted: @Sendable () async -> Void

    init(
        install: @escaping @Sendable () async throws -> Void,
        markPrompted: @escaping @Sendable () async -> Void
    ) {
        self.install = install
        self.markPrompted = markPrompted
    }

    /// macOS 26 with the transcriber available, the model absent and the user not
    /// yet asked — every other combination stays silent.
    static func shouldPrompt(osMajor: Int, status: AssetStatus, alreadyPrompted: Bool) -> Bool {
        osMajor >= 26 && status == .notInstalled && !alreadyPrompted
    }

    /// Both answers record `speech_model_prompted`, so the dialog appears once.
    func choose(_ choice: Choice) async {
        await markPrompted()
        guard choice == .download else { return }
        do {
            try await install()
        } catch {
            Log.ui.error("Speech model download failed: \(AnyError(error).description)")
        }
    }

    @MainActor
    static func ask() -> Choice {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Download the on-device speech model?"
        alert.informativeText = """
            Apple's on-device speech model gives the most accurate live transcript and \
            never leaves this Mac. It downloads in the background; you can also start \
            the download later under Settings → General.
            """
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Not now")
        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        return response == .alertFirstButtonReturn ? .download : .notNow
    }
}
