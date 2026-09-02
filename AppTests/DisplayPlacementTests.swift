import CoreGraphics
import MWOverlaySim
import Testing
@testable import MiniWhisper

private struct StubFocusedWindow: FocusedWindowProviding {
    var frame: CGRect?
    func focusedWindowFrame(pid: pid_t) -> CGRect? { frame }
}

private struct StubPointer: PointerLocationProviding {
    var point: CGPoint
    func location() -> CGPoint { point }
}

private struct StubScreens: ScreenListing {
    var all: [CGRect]
    var main: CGRect?
    func frames() -> [CGRect] { all }
    func mainFrame() -> CGRect? { main }
}

@Suite struct DisplayPlacementTests {
    // Primary 1920×1080 at the origin, secondary 1440×900 to its right.
    private let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let secondary = CGRect(x: 1920, y: 0, width: 1440, height: 900)

    private func placement(
        window: CGRect?,
        mouse: CGPoint,
        main: CGRect? = nil
    ) -> DisplayPlacement {
        DisplayPlacement(
            focused: StubFocusedWindow(frame: window),
            pointer: StubPointer(point: mouse),
            screens: StubScreens(all: [primary, secondary], main: main ?? primary)
        )
    }

    @Test func prefersScreenContainingFocusedWindowCentre() {
        // AX coordinates are top-left origin: y 100 on the secondary screen.
        let window = CGRect(x: 2400, y: 100, width: 400, height: 300)
        let resolver = placement(window: window, mouse: CGPoint(x: 10, y: 10))
        #expect(resolver.screenFrame(forPID: 42) == secondary)
    }

    @Test func fallsBackToMouseScreen() {
        let resolver = placement(window: nil, mouse: CGPoint(x: 2500, y: 400))
        #expect(resolver.screenFrame(forPID: 42) == secondary)
        #expect(placement(window: nil, mouse: CGPoint(x: 100, y: 100)).screenFrame(forPID: 42) == primary)
    }

    @Test func fallsBackToMainScreen() {
        let offscreen = CGPoint(x: -5000, y: -5000)
        let resolver = placement(window: nil, mouse: offscreen, main: secondary)
        #expect(resolver.screenFrame(forPID: nil) == secondary)
    }

    // `#expect` does not apply the implicit CGFloat/Double conversion, so every
    // comparison against a `Constants` value converts explicitly.
    @Test func cardAndCaptionGeometryMatchTheDesign() {
        let card = DisplayPlacement.cardFrame(on: primary)
        #expect(Double(card.width) == Constants.windowSize)
        #expect(Double(card.height) == Constants.windowSize)
        #expect(card.midX == primary.midX)
        #expect(card.midY == primary.midY)

        let caption = DisplayPlacement.captionFrame(card: card)
        #expect(caption.minX == card.minX - 90)
        #expect(Double(caption.minY) == Double(card.minY) - Constants.captionGap - Constants.captionHeight)
        #expect(Double(caption.width) == Constants.captionWidth)
        #expect(Double(caption.height) == Constants.captionHeight)
    }
}
