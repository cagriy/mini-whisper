import AppKit
import MWOverlaySim

/// The recording card: places the panel on the target display, runs the configured
/// style's animator at the display's refresh rate and hides itself when a mode's
/// choreography finishes (§5.6, F9, F14, F37). A style change stored by `setStyle` is
/// picked up at the next `show(on:)`, never mid-animation (R3).
@MainActor
final class OverlayPanelController {
    private let panel: OverlayPanel
    private let reduceMotion: Bool
    private var style: OverlayStyle
    private var animator: any OverlayAnimator
    private var driver: DisplayLinkDriver?
    private var level = 0.0

    init(style: OverlayStyle, reduceMotion: Bool) {
        self.style = style
        self.reduceMotion = reduceMotion
        animator = OverlayAnimatorFactory.make(style: style, reduceMotion: reduceMotion)
        let side = Constants.windowSize
        panel = OverlayPanel(size: CGSize(width: side, height: side))
        panel.hostLayer?.addSublayer(animator.layer)
        if let view = panel.contentView {
            driver = DisplayLinkDriver(view: view) { [weak self] dt in self?.step(dt) }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func setStyle(_ style: OverlayStyle) {
        self.style = style
    }

    /// N1: the first frame is drawn before the panel is ordered in, so the card is
    /// complete on the very frame it appears.
    func show(on screen: CGRect) {
        if animator.style != style {
            animator.layer.removeFromSuperlayer()
            animator = OverlayAnimatorFactory.make(style: style, reduceMotion: reduceMotion)
            panel.hostLayer?.addSublayer(animator.layer)
        }
        panel.setFrame(DisplayPlacement.cardFrame(on: screen), display: false)
        animator.setContentsScale(panel.screen?.backingScaleFactor ?? 2)
        level = 0
        animator.show()
        animator.step(dt: 0, level: 0)
        panel.orderFrontRegardless()
        driver?.start()
    }

    func set(mode: OverlayMode) {
        guard panel.isVisible else { return }
        animator.set(mode: mode)
    }

    func setLevel(_ rms: Float) {
        level = Double(rms)
    }

    func hide() {
        driver?.stop()
        panel.orderOut(nil)
    }

    private func step(_ dt: TimeInterval) {
        animator.step(dt: dt, level: level)
        if animator.isFinished { hide() }
    }
}
