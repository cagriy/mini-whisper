import AppKit
import MWPipeline
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct FrontAppTrackerTests {
    /// The one running app a test can count on: the test host. Whether it is "another app"
    /// or Mini Whisper itself is decided by the process id the tracker is told is its own.
    private let host = NSRunningApplication.current
    private let center = NotificationCenter()
    private static let anotherProcess: pid_t = 0

    private var target: PasteTarget {
        PasteTarget(pid: host.processIdentifier, name: host.localizedName ?? "", bundleID: host.bundleIdentifier)
    }

    private func activate() {
        center.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: host]
        )
    }

    @Test func startsWithTheFrontmostApp() {
        let tracker = FrontAppTracker(center: center, frontmost: host, ownPID: Self.anotherProcess)

        #expect(tracker.previousApp == target)
    }

    @Test func startsEmptyWhenMiniWhisperIsFrontmost() {
        let tracker = FrontAppTracker(center: center, frontmost: host, ownPID: host.processIdentifier)

        #expect(tracker.previousApp == nil)
    }

    @Test func startsEmptyWithoutAFrontmostApp() {
        let tracker = FrontAppTracker(center: center, frontmost: nil, ownPID: Self.anotherProcess)

        #expect(tracker.previousApp == nil)
    }

    @Test func anotherAppActivatingBecomesTheTarget() {
        let tracker = FrontAppTracker(center: center, frontmost: nil, ownPID: Self.anotherProcess)

        activate()

        #expect(tracker.previousApp == target)
    }

    @Test func miniWhisperActivatingIsIgnored() {
        let tracker = FrontAppTracker(center: center, frontmost: nil, ownPID: host.processIdentifier)

        activate()

        #expect(tracker.previousApp == nil)
    }
}
