import ApplicationServices
import MWPaste

/// `AXIsProcessTrusted()` behind the paste-time trust check (§5.8).
struct AXTrustCheck: AccessibilityCheck {
    var isTrusted: Bool { AXIsProcessTrusted() }
}
