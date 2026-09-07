import AppKit
import MWOverlaySim
import QuartzCore

/// A source of frame ticks a host starts and stops. `DisplayLinkDriver` is the one
/// implementation; the Settings preview takes it as a parameter so its tests never
/// build a `CADisplayLink`.
@MainActor
protocol FrameDriving: AnyObject {
    var isRunning: Bool { get }
    func start()
    func stop()
}

/// Frame ticks at the display's refresh rate (§5.6). `dt` is clamped exactly as
/// `overlay.py`'s `_tick` clamps it, so a stall cannot explode the physics.
@MainActor
final class DisplayLinkDriver: FrameDriving {
    private weak var view: NSView?
    private let onTick: (TimeInterval) -> Void
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    init(view: NSView, onTick: @escaping (TimeInterval) -> Void) {
        self.view = view
        self.onTick = onTick
    }

    var isRunning: Bool { link != nil }

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
