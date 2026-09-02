import CoreGraphics
import Foundation
import MWConfig
import MWSupport
import MWTestSupport
import Testing

import MWPaste

/// The paste sequence of F25 and design §5.7's paste rows, driven entirely through the
/// injected seams — no test posts a real key event or touches the real pasteboard.
@Suite struct PasterTests {
    private struct StubAccessibility: AccessibilityCheck {
        let isTrusted: Bool
    }

    private struct StubProcess: ProcessCheck {
        let running: Bool
        func isRunning(pid: pid_t) -> Bool { running }
    }

    private static let target: pid_t = 4242

    private static let snapshot = PasteboardSnapshot(items: [
        ["public.utf8-plain-text": Data("original".utf8), "public.html": Data("<p>original</p>".utf8)],
        ["public.png": Data([0x89, 0x50, 0x4E, 0x47])],
    ])

    private struct Harness {
        let paster: Paster
        let poster = FakeKeyPoster()
        let pasteboard: FakePasteboard
        let clock = VirtualClock()

        init(trusted: Bool = true, running: Bool = true) {
            pasteboard = FakePasteboard(contents: PasterTests.snapshot)
            paster = Paster(
                pasteboard: pasteboard,
                poster: poster,
                accessibility: StubAccessibility(isTrusted: trusted),
                process: StubProcess(running: running),
                clock: clock
            )
        }
    }

    private func down(_ keyCode: CGKeyCode, _ flags: CGEventFlags = []) -> FakeKeyPoster.Event {
        FakeKeyPoster.Event(keyCode: keyCode, flags: flags, down: true, pid: Self.target)
    }

    private func up(_ keyCode: CGKeyCode, _ flags: CGEventFlags = []) -> FakeKeyPoster.Event {
        FakeKeyPoster.Event(keyCode: keyCode, flags: flags, down: false, pid: Self.target)
    }

    private var commandV: [FakeKeyPoster.Event] { [down(9, .maskCommand), up(9, .maskCommand)] }

    @Test func postsCmdVDownUpToTargetPid() async throws {
        let harness = Harness()
        let task = Task { try await harness.paster.paste("hello", into: Self.target, submit: nil) }

        await harness.clock.waitUntilSleeping()
        #expect(harness.poster.events == commandV)

        harness.clock.advance(by: 0.3)
        try await task.value
    }

    /// The source slept 50 ms between the clipboard write and ⌘V; the write is synchronous
    /// here, so the first sleep of the whole sequence comes *after* the key events.
    @Test func postsImmediatelyAfterWrite() async throws {
        let harness = Harness()
        let task = Task { try await harness.paster.paste("hello", into: Self.target, submit: nil) }

        await harness.clock.waitUntilSleeping()
        #expect(harness.pasteboard.written == ["hello"])
        #expect(harness.poster.events == commandV)

        harness.clock.advance(by: 0.3)
        try await task.value
    }

    @Test func submitEnterPosted150msLater() async throws {
        let harness = Harness()
        let task = Task { try await harness.paster.paste("hello", into: Self.target, submit: .enter) }

        await harness.clock.waitUntilSleeping()
        #expect(harness.poster.events == commandV)

        harness.clock.advance(by: 0.15)
        await harness.clock.waitUntilSleeping()
        #expect(harness.poster.events == commandV + [down(36), up(36)])

        harness.clock.advance(by: 0.3)
        try await task.value
    }

    @Test func submitShiftEnterFlags() async throws {
        let harness = Harness()
        let task = Task {
            try await harness.paster.paste("hello", into: Self.target, submit: .shiftEnter)
        }

        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 0.15)
        await harness.clock.waitUntilSleeping()
        #expect(harness.poster.events == commandV + [down(36, .maskShift), up(36, .maskShift)])

        harness.clock.advance(by: 0.3)
        try await task.value
    }

    @Test func submitCmdEnterFlags() async throws {
        let harness = Harness()
        let task = Task {
            try await harness.paster.paste("hello", into: Self.target, submit: .cmdEnter)
        }

        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 0.15)
        await harness.clock.waitUntilSleeping()
        #expect(harness.poster.events == commandV + [down(36, .maskCommand), up(36, .maskCommand)])

        harness.clock.advance(by: 0.3)
        try await task.value
    }

    @Test func noSubmitWhenNil() async throws {
        let harness = Harness()
        let task = Task { try await harness.paster.paste("hello", into: Self.target, submit: nil) }

        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 0.3)
        try await task.value

        #expect(harness.poster.events == commandV)
    }

    @Test func restoresSnapshotAfter300msWhenUnchanged() async throws {
        let harness = Harness()
        let task = Task { try await harness.paster.paste("hello", into: Self.target, submit: nil) }

        await harness.clock.waitUntilSleeping()
        #expect(harness.pasteboard.restored.isEmpty)

        harness.clock.advance(by: 0.3)
        try await task.value

        #expect(harness.pasteboard.restored == [Self.snapshot])
    }

    @Test func doesNotRestoreWhenChangeCountMoved() async throws {
        let harness = Harness()
        let task = Task { try await harness.paster.paste("hello", into: Self.target, submit: nil) }

        await harness.clock.waitUntilSleeping()
        harness.pasteboard.changeExternally()
        harness.clock.advance(by: 0.3)
        try await task.value

        #expect(harness.pasteboard.restored.isEmpty)
    }

    @Test func restoreTimingCountsFromLastSyntheticEvent() async throws {
        let harness = Harness()
        let task = Task { try await harness.paster.paste("hello", into: Self.target, submit: .enter) }

        await harness.clock.waitUntilSleeping()
        harness.clock.advance(by: 0.15)
        await harness.clock.waitUntilSleeping()

        // 300 ms after ⌘V but only 150 ms after the submit key: still no restore.
        harness.clock.advance(by: 0.299)
        #expect(harness.pasteboard.restored.isEmpty)

        harness.clock.advance(by: 0.001)
        try await task.value
        #expect(harness.pasteboard.restored == [Self.snapshot])
    }

    @Test func accessibilityUntrustedThrowsAndPostsNothing() async throws {
        let harness = Harness(trusted: false)

        await #expect(throws: PasteError.accessibilityLost) {
            try await harness.paster.paste("hello", into: Self.target, submit: nil)
        }
        #expect(harness.poster.events.isEmpty)
        #expect(harness.pasteboard.written.isEmpty)
        #expect(harness.pasteboard.restored.isEmpty)
        #expect(
            PasteError.accessibilityLost.userMessage
                == "Accessibility permission lost — re-enable in System Settings"
        )
    }

    @Test func deadPidThrowsTargetGone() async throws {
        let harness = Harness(running: false)

        await #expect(throws: PasteError.targetGone) {
            try await harness.paster.paste("hello", into: Self.target, submit: nil)
        }
        #expect(harness.poster.events.isEmpty)
        #expect(harness.pasteboard.restored == [Self.snapshot])
        #expect(PasteError.targetGone.userMessage == "Target app is no longer running")
    }

    @Test func writesAllSnapshotItemsAndTypesBack() async throws {
        let harness = Harness()
        let task = Task { try await harness.paster.paste("hello", into: Self.target, submit: nil) }

        await harness.clock.waitUntilSleeping()
        #expect(harness.pasteboard.contents != Self.snapshot)

        harness.clock.advance(by: 0.3)
        try await task.value

        #expect(harness.pasteboard.contents == Self.snapshot)
    }
}
