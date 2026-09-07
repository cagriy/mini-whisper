import AppKit
import MWOverlaySim
import SwiftUI

/// The Overlay pane's 300×300 preview: the card's own animator replaying
/// `PreviewScript`'s 13 s dictation with a simulated voice, forever (design §5.6,
/// R13). It runs only while the view is in a window, so leaving the pane or closing
/// Settings costs nothing (R14). The driver and the animator arrive as factories so
/// the tests drive the loop on injected `dt` without a `CADisplayLink`.
@MainActor
final class OverlayPreviewView: NSView {
    private let makeAnimator: (OverlayStyle) -> any OverlayAnimator
    private var animator: any OverlayAnimator
    private var driver: (any FrameDriving)?
    private var appliedMode: OverlayMode?

    private(set) var loopTime: TimeInterval = 0

    init(
        style: OverlayStyle,
        makeDriver: (NSView, @escaping (TimeInterval) -> Void) -> any FrameDriving = {
            DisplayLinkDriver(view: $0, onTick: $1)
        },
        makeAnimator: @escaping (OverlayStyle) -> any OverlayAnimator = {
            OverlayAnimatorFactory.make(
                style: $0,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        }
    ) {
        self.makeAnimator = makeAnimator
        animator = makeAnimator(style)
        let side = Constants.windowSize
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        wantsLayer = true
        layer?.addSublayer(animator.layer)
        driver = makeDriver(self) { [weak self] dt in self?.tick(dt) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not in a nib") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            driver?.stop()
            return
        }
        animator.setContentsScale(window.backingScaleFactor)
        startLoop(at: 0)
        driver?.start()
    }

    /// R12: a new style restarts the loop; every other `updateNSView` leaves it alone.
    func setStyle(_ style: OverlayStyle) {
        guard style != animator.style else { return }
        animator.layer.removeFromSuperlayer()
        animator = makeAnimator(style)
        animator.setContentsScale(window?.backingScaleFactor ?? 2)
        layer?.addSublayer(animator.layer)
        startLoop(at: 0)
    }

    func stop() {
        driver?.stop()
    }

    func tick(_ dt: TimeInterval) {
        loopTime += dt
        if loopTime >= PreviewScript.loopSeconds {
            startLoop(at: loopTime - PreviewScript.loopSeconds)
        }
        let mode = PreviewScript.mode(at: loopTime)
        if mode != appliedMode {
            appliedMode = mode
            animator.set(mode: mode)
        }
        animator.step(dt: dt, level: PreviewScript.simulatedRMS(at: loopTime))
    }

    private func startLoop(at time: TimeInterval) {
        loopTime = time
        appliedMode = nil
        animator.show()
    }
}

struct OverlayPreview: NSViewRepresentable {
    let style: OverlayStyle

    func makeNSView(context: Context) -> OverlayPreviewView {
        OverlayPreviewView(style: style)
    }

    func updateNSView(_ view: OverlayPreviewView, context: Context) {
        view.setStyle(style)
    }

    static func dismantleNSView(_ view: OverlayPreviewView, coordinator: ()) {
        view.stop()
    }
}
