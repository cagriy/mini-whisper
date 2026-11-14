import AVFoundation
import AppKit
import ApplicationServices
import MWSupport
import SwiftUI

extension PermissionMonitor {
    static func granted(_ permission: OnboardingPermission) -> Bool {
        switch permission {
        case .microphone: microphoneGranted
        case .accessibility: accessibilityGranted
        }
    }

    /// Triggers the system prompt for one permission. The microphone prompt only
    /// exists while the status is undetermined; Accessibility is asked for with the
    /// trust-check option (`onboarding.py:_request_permission`).
    static func request(_ permission: OnboardingPermission) {
        switch permission {
        case .microphone:
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .accessibility:
            // The literal name, as `onboarding.py` uses: the `kAXTrustedCheckOptionPrompt`
            // global is a `var` and so not readable under Swift 6 strict concurrency.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }
}

/// F33's wizard: `OnboardingView` over `OnboardingModel`, the 1.5 s poll, unclosable, and a
/// Continue that starts normal operation in this process rather than relaunching the bundle as
/// `onboarding.py:_on_continue` does.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let onContinue: () -> Void
    let window = NSWindow.small(title: "Mini Whisper — Setup", size: CGSize(width: 460, height: 330), closable: false)
    private var model: OnboardingModel
    private var timer: Timer?
    private var host: NSHostingView<OnboardingView>?

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        model = OnboardingModel(
            isGranted: { PermissionMonitor.granted($0) },
            request: { PermissionMonitor.request($0) }
        )
        super.init()
        window.delegate = self
        host = window.host(view)
    }

    func show() {
        model.start()
        refresh()

        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated { self.poll() }
        }
        self.timer = timer

        WindowActivation.shown(window)
    }

    /// The window cannot be dismissed while a permission is missing (F33).
    func windowShouldClose(_ sender: NSWindow) -> Bool { false }

    private var view: OnboardingView {
        OnboardingView(
            model: model,
            openSettings: { NSWorkspace.shared.open($0.settingsURL) },
            proceed: { [weak self] in self?.proceed() }
        )
    }

    private func poll() {
        model.poll()
        refresh()
    }

    private func refresh() {
        host?.rootView = view
    }

    private func proceed() {
        timer?.invalidate()
        timer = nil
        window.delegate = nil
        window.close()
        WindowActivation.closed()
        Log.ui.info("Onboarding complete; starting in-process")
        onContinue()
    }
}
