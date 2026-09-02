import CoreGraphics
import Foundation
import MWConfig
import MWSupport

/// Delivering text to another application, so the pipeline can be exercised without
/// posting real key events.
public protocol Pasting: Sendable {
    func paste(_ text: String, into pid: pid_t, submit: SubmitKey?) async throws
}

/// `AXIsProcessTrusted()` behind a seam — the trust check runs before any post (§5.8).
public protocol AccessibilityCheck: Sendable {
    var isTrusted: Bool { get }
}

/// `NSRunningApplication(processIdentifier:)` behind a seam (§5.7).
public protocol ProcessCheck: Sendable {
    func isRunning(pid: pid_t) -> Bool
}

/// F25's paste sequence: snapshot, write, ⌘V to the target pid, optional submit key
/// 150 ms later, and a restore 300 ms after the last synthetic event if the user has
/// not copied anything in the meantime.
public struct Paster: Pasting {
    private static let submitDelay = Duration.seconds(0.15)
    private static let restoreWindow = Duration.seconds(0.3)

    private let pasteboard: any PasteboardAccess
    private let poster: any KeyPoster
    private let accessibility: any AccessibilityCheck
    private let process: any ProcessCheck
    private let clock: any Clock

    public init(
        pasteboard: any PasteboardAccess,
        poster: any KeyPoster,
        accessibility: any AccessibilityCheck,
        process: any ProcessCheck,
        clock: any Clock
    ) {
        self.pasteboard = pasteboard
        self.poster = poster
        self.accessibility = accessibility
        self.process = process
        self.clock = clock
    }

    public func paste(_ text: String, into pid: pid_t, submit: SubmitKey?) async throws {
        guard accessibility.isTrusted else { throw PasteError.accessibilityLost }

        let snapshot = pasteboard.snapshot()
        // The source slept 50 ms here; the write is synchronous, so ⌘V follows it directly.
        let ours = pasteboard.write(text)

        guard process.isRunning(pid: pid) else {
            pasteboard.restore(snapshot)
            throw PasteError.targetGone
        }

        post(SubmitKeyCodes.v, flags: .maskCommand, to: pid)
        if let submit {
            try await clock.sleep(for: Self.submitDelay)
            let stroke = SubmitKeyCodes.stroke(for: submit)
            post(stroke.keyCode, flags: stroke.flags, to: pid)
        }

        try await clock.sleep(for: Self.restoreWindow)
        guard pasteboard.changeCount == ours else { return }
        pasteboard.restore(snapshot)
    }

    private func post(_ keyCode: CGKeyCode, flags: CGEventFlags, to pid: pid_t) {
        poster.post(keyCode: keyCode, flags: flags, down: true, pid: pid)
        poster.post(keyCode: keyCode, flags: flags, down: false, pid: pid)
    }
}
