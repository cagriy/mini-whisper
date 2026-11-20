import AppKit
import SwiftUI

/// About Mini Whisper (design §5.9, R24): a 300 by 330 window that closes from its close button.
/// Its Credits… opens one Credits window, made at the first press and brought forward after.
@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    let window = NSWindow.small(title: "About Mini Whisper", size: CGSize(width: 300, height: 330))
    private lazy var credits = CreditsWindowController()

    override init() {
        super.init()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        window.titleVisibility = .hidden
        window.host(AboutView(version: version, showCredits: { [weak self] in self?.credits.show() }))
        window.delegate = self
    }

    func show() {
        WindowActivation.shown(window)
    }

    func windowWillClose(_ notification: Notification) {
        WindowActivation.closed()
    }
}
