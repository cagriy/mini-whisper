import AppKit

/// The About alert, with the source's text and the bundle's version.
@MainActor
enum AboutPanel {
    static func show() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Mini Whisper"
        alert.informativeText = """
            Version \(version)

            Hold your hotkey to talk, or tap to toggle recording.
            Transcribed text is pasted into the active app.

            Powered by OpenAI gpt-4o-mini-transcribe.
            """
        alert.runModal()
        NSApp.setActivationPolicy(.accessory)
    }
}
