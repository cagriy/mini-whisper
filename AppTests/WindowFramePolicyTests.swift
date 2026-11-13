import CoreGraphics
import MWConfig
import Testing
@testable import MiniWhisper

@Suite struct WindowFramePolicyTests {
    // Visible frames: the main screen at the origin, a larger one to its right.
    private static let main = CGRect(x: 0, y: 0, width: 1260, height: 840)
    private static let second = CGRect(x: 1260, y: 0, width: 1920, height: 1080)
    private static let screens = WindowFramePolicy.Screens(visible: [main, second], main: main)
    private static let defaultFrame = CGRect(x: 90, y: 60, width: 1080, height: 720)

    private func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
        WindowFramePolicy.frame(saved: WindowFrame(x: x, y: y, width: width, height: height), screens: Self.screens)
    }

    @Test func noSavedFrameGivesTheDefaultCentredOnTheMainScreen() {
        #expect(WindowFramePolicy.frame(saved: nil, screens: Self.screens) == Self.defaultFrame)
    }

    @Test func aSavedFrameOnAScreenIsReturnedAsIs() {
        #expect(frame(120, 80, 1000, 700) == CGRect(x: 120, y: 80, width: 1000, height: 700))
        #expect(frame(1400, 100, 1600, 900) == CGRect(x: 1400, y: 100, width: 1600, height: 900))
    }

    @Test func aFrameOnADisconnectedDisplayGivesTheDefault() {
        #expect(frame(-3000, 200, 1080, 720) == Self.defaultFrame)
    }

    @Test func aFrameOverlappingAScreenByLessThan100By100GivesTheDefault() {
        // 99 points wide on the main screen, nothing on the second.
        #expect(frame(-901, 100, 1000, 700) == Self.defaultFrame)
        // 99 points high.
        #expect(frame(100, -601, 1000, 700) == Self.defaultFrame)
    }

    @Test func aFrameOverlappingAScreenBy100By100IsMovedOntoIt() {
        #expect(frame(-900, -600, 1000, 700) == CGRect(x: 0, y: 0, width: 1000, height: 700))
    }

    @Test func aTooSmallFrameIsRaisedToTheMinimum() {
        #expect(frame(100, 100, 400, 300) == CGRect(x: 100, y: 100, width: 900, height: 600))
        #expect(frame(100, 100, 1000, 300) == CGRect(x: 100, y: 100, width: 1000, height: 600))
    }

    @Test func aRaisedFrameIsKeptOnItsScreen() {
        #expect(frame(1000, 700, 200, 120) == CGRect(x: 360, y: 240, width: 900, height: 600))
    }

    @Test func aFrameLargerThanItsScreenIsClampedToTheVisibleFrame() {
        #expect(frame(-50, -50, 1340, 2000) == Self.main)
        #expect(frame(100, 50, 2000, 700) == CGRect(x: 0, y: 50, width: 1260, height: 700))
    }

    @Test func aFrameAcrossTwoScreensGoesToTheOneHoldingMoreOfIt() {
        // 260 points on the main screen, 740 on the second.
        #expect(frame(1000, 100, 1000, 700) == CGRect(x: 1260, y: 100, width: 1000, height: 700))
    }

    @Test func withoutAMainScreenTheDefaultSitsAtTheOrigin() {
        let none = WindowFramePolicy.Screens(visible: [], main: nil)
        let saved = WindowFrame(x: 120, y: 80, width: 1000, height: 700)
        #expect(WindowFramePolicy.frame(saved: saved, screens: none) == CGRect(x: 0, y: 0, width: 1080, height: 720))
        #expect(WindowFramePolicy.frame(saved: nil, screens: none) == CGRect(x: 0, y: 0, width: 1080, height: 720))
    }

    @Test func sizesMatchTheRequirement() {
        #expect(WindowFramePolicy.defaultSize == CGSize(width: 1080, height: 720))
        #expect(WindowFramePolicy.minimumSize == CGSize(width: 900, height: 600))
    }
}
