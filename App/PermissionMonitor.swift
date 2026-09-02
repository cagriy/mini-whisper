import AVFoundation
import ApplicationServices

/// The two TCC grants the app cannot work without (`onboarding.check_*`).
enum PermissionMonitor {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static var allGranted: Bool {
        microphoneGranted && accessibilityGranted
    }
}
