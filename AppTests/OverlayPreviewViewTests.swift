import AppKit
import CoreGraphics
import MWOverlaySim
import Testing
@testable import MiniWhisper

/// The Settings preview's loop and lifecycle (design §5.6, R13, R14), driven entirely
/// on injected `dt`: no `CADisplayLink`, no real time.
@Suite @MainActor struct OverlayPreviewViewTests {
    private final class FakeDriver: FrameDriving {
        private(set) var isRunning = false

        func start() { isRunning = true }
        func stop() { isRunning = false }
    }

    private final class SpyAnimator: OverlayAnimator {
        let style: OverlayStyle
        let layer = CALayer()
        var isFinished = false
        private(set) var shows = 0
        private(set) var modes: [OverlayMode] = []
        private(set) var levels: [Double] = []

        init(style: OverlayStyle) { self.style = style }

        func show() { shows += 1 }
        func set(mode: OverlayMode) { modes.append(mode) }
        func step(dt: TimeInterval, level: Double) { levels.append(level) }
        func setContentsScale(_ scale: CGFloat) {}
    }

    @MainActor private final class Harness {
        let driver = FakeDriver()
        private(set) var animators: [SpyAnimator] = []
        private let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 316, height: 316),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )

        lazy var view = OverlayPreviewView(
            style: .softMeter,
            makeDriver: { [driver] _, _ in driver },
            makeAnimator: { [unowned self] style in
                let animator = SpyAnimator(style: style)
                animators.append(animator)
                return animator
            }
        )

        var animator: SpyAnimator { animators[animators.count - 1] }

        func attach() { window.contentView?.addSubview(view) }
        func detach() { view.removeFromSuperview() }
        func tick(_ count: Int, dt: TimeInterval = 0.05) {
            for _ in 0..<count { view.tick(dt) }
        }
    }

    @Test func attachingToAWindowStartsTheDriverAndShows() {
        let harness = Harness()
        harness.attach()

        #expect(harness.driver.isRunning)
        #expect(harness.animator.shows == 1)
        #expect(harness.view.loopTime == 0)
    }

    @Test func leavingTheWindowStopsTheDriver() {
        let harness = Harness()
        harness.attach()
        harness.detach()

        #expect(!harness.driver.isRunning)
    }

    @Test func dismantleStopsTheDriver() {
        let harness = Harness()
        harness.attach()

        OverlayPreview.dismantleNSView(harness.view, coordinator: ())

        #expect(!harness.driver.isRunning)
    }

    @Test func styleChangeRebuildsTheAnimatorAndResetsTheLoop() {
        let harness = Harness()
        harness.attach()
        harness.tick(100)
        #expect(harness.view.loopTime > 0)

        harness.view.setStyle(.petalIris)

        #expect(harness.animators.count == 2)
        #expect(harness.animator.style == .petalIris)
        #expect(harness.animator.shows == 1)
        #expect(harness.view.loopTime == 0)

        // SwiftUI re-runs `updateNSView` on every state change; only a different
        // style may restart the loop (R12).
        harness.tick(10)
        harness.view.setStyle(.petalIris)
        #expect(harness.animators.count == 2)
        #expect(harness.view.loopTime > 0)
    }

    @Test func thirteenSecondsOfTicksWrapsAndCallsShowAgain() {
        let harness = Harness()
        harness.attach()

        harness.tick(Int(PreviewScript.loopSeconds / 0.05))

        #expect(harness.animator.shows == 2)
        #expect(harness.view.loopTime < 0.05)
        #expect(harness.animators.count == 1)
    }

    @Test func modeFollowsThePreviewScript() {
        let harness = Harness()
        harness.attach()

        // One tick short of the wrap, so the sequence is exactly one loop.
        harness.tick(Int(PreviewScript.loopSeconds / 0.05) - 1)

        #expect(harness.animator.modes == [.starting, .recording, .processing, .result])
        #expect(harness.animator.levels.last == PreviewScript.simulatedRMS(at: harness.view.loopTime))
    }
}
