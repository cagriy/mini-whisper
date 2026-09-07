import CoreGraphics
import Foundation
import MWOverlaySim
import Testing
@testable import MiniWhisper

private let otherStyles = OverlayStyle.allCases.filter { $0 != .constellation }

/// The seam the card and the Settings preview share (design §5.1, §5.12).
@Suite @MainActor struct OverlayAnimatorTests {
    private func make(_ style: OverlayStyle) -> any OverlayAnimator {
        OverlayAnimatorFactory.make(style: style, reduceMotion: false)
    }

    @Test func factoryReturnsConstellationForConstellation() {
        #expect(make(.constellation) is ConstellationAnimator)
    }

    @Test(arguments: otherStyles)
    func factoryReturnsStyleAnimatorForEveryOtherStyle(_ style: OverlayStyle) {
        #expect(make(style) is StyleAnimator)
    }

    @Test(arguments: OverlayStyle.allCases)
    func animatorStyleMatchesWhatItWasMadeFor(_ style: OverlayStyle) {
        #expect(make(style).style == style)
    }

    @Test(arguments: OverlayStyle.allCases)
    func isFinishedPropagatesFromTheSimulation(_ style: OverlayStyle) {
        let animator = make(style)
        animator.show()
        animator.set(mode: .result)
        animator.step(dt: 0, level: 0)
        #expect(!animator.isFinished)

        // 400 ms: past the 260 ms hold plus the 120 ms fade.
        for _ in 0..<10 { animator.step(dt: 0.04, level: 0) }
        #expect(animator.isFinished)
    }

    @Test(arguments: OverlayStyle.allCases)
    func layerIsSizedToTheCard(_ style: OverlayStyle) {
        let side = Constants.windowSize
        #expect(make(style).layer.frame == CGRect(x: 0, y: 0, width: side, height: side))
    }
}
