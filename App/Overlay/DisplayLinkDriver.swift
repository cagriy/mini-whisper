import AppKit
import MWOverlaySim
import QuartzCore

/// Frame ticks at the display's refresh rate (§5.6). `dt` is clamped exactly as
/// `overlay.py`'s `_tick` clamps it, so a stall cannot explode the physics.
@MainActor
final class DisplayLinkDriver {
    private weak var view: NSView?
    private let onTick: (TimeInterval) -> Void
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    init(view: NSView, onTick: @escaping (TimeInterval) -> Void) {
        self.view = view
        self.onTick = onTick
    }

    func start() {
        guard link == nil, let view else { return }
        last = CACurrentMediaTime()
        let link = view.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = min(now - last, Constants.maxTimestep)
        last = now
        onTick(elapsed)
    }
}
