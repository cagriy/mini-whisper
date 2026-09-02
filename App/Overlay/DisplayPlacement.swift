import AppKit
import ApplicationServices
import MWOverlaySim

/// The frontmost app's focused window, in Accessibility coordinates (origin at the
/// top-left of the primary display, y growing downwards).
protocol FocusedWindowProviding: Sendable {
    func focusedWindowFrame(pid: pid_t) -> CGRect?
}

protocol PointerLocationProviding: Sendable {
    func location() -> CGPoint
}

protocol ScreenListing: Sendable {
    /// Cocoa screen frames; the first is the primary display.
    func frames() -> [CGRect]
    func mainFrame() -> CGRect?
}

/// F37: the panels are placed on the display holding the frontmost app's focused
/// window, else the display under the mouse, else the main display — recomputed on
/// every show (§5.6).
struct DisplayPlacement {
    let focused: any FocusedWindowProviding
    let pointer: any PointerLocationProviding
    let screens: any ScreenListing

    func screenFrame(forPID pid: pid_t?) -> CGRect {
        let all = screens.frames()
        if let pid, let window = focused.focusedWindowFrame(pid: pid),
           let screen = screen(containing: CGPoint(x: window.midX, y: window.midY), flipped: true, in: all) {
            return screen
        }
        if let screen = screen(containing: pointer.location(), flipped: false, in: all) {
            return screen
        }
        return screens.mainFrame() ?? all.first ?? .zero
    }

    static func cardFrame(on screen: CGRect) -> CGRect {
        CGRect(
            x: screen.midX - Constants.windowSize / 2,
            y: screen.midY - Constants.windowSize / 2,
            width: Constants.windowSize,
            height: Constants.windowSize
        )
    }

    static func captionFrame(card: CGRect) -> CGRect {
        CGRect(
            x: card.minX - (Constants.captionWidth - Constants.windowSize) / 2,
            y: card.minY - Constants.captionGap - Constants.captionHeight,
            width: Constants.captionWidth,
            height: Constants.captionHeight
        )
    }

    /// The far off-screen origin panels are built at, so they exist before the first
    /// press without ever being seen (§5.5 Launch).
    static let offscreenOrigin = CGPoint(x: -10_000, y: -10_000)

    private func screen(containing point: CGPoint, flipped: Bool, in all: [CGRect]) -> CGRect? {
        guard let primary = all.first else { return nil }
        let cocoa = flipped ? CGPoint(x: point.x, y: primary.maxY - point.y) : point
        return all.first { $0.contains(cocoa) }
    }
}

struct AXFocusedWindow: FocusedWindowProviding {
    func focusedWindowFrame(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let element = window
        else { return nil }
        let axWindow = element as! AXUIElement

        guard let origin: CGPoint = value(of: axWindow, kAXPositionAttribute, .cgPoint),
              let size: CGSize = value(of: axWindow, kAXSizeAttribute, .cgSize)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func value<T>(of element: AXUIElement, _ attribute: String, _ type: AXValueType) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let value = raw
        else { return nil }
        let axValue = value as! AXValue
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(axValue, type, result) else { return nil }
        return result.pointee
    }
}

struct NSEventPointer: PointerLocationProviding {
    func location() -> CGPoint { NSEvent.mouseLocation }
}

struct NSScreenList: ScreenListing {
    func frames() -> [CGRect] { NSScreen.screens.map(\.frame) }
    func mainFrame() -> CGRect? { NSScreen.main?.frame }
}
