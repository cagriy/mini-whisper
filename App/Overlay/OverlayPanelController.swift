import AppKit
import MWOverlaySim

/// The constellation card: places the panel on the target display, runs the
/// simulation at the display's refresh rate and hides itself when a mode's
/// choreography finishes (§5.6, F9, F14, F37).
@MainActor
final class OverlayPanelController {
    private let panel: OverlayPanel
    private let constellation = ConstellationLayer()
    private var simulation: ConstellationSimulation
    private var driver: DisplayLinkDriver?
    private var level = 0.0

    init(reduceMotion: Bool) {
        simulation = ConstellationSimulation(reduceMotion: reduceMotion)
        let side = Constants.windowSize
        panel = OverlayPanel(size: CGSize(width: side, height: side))
        constellation.frame = CGRect(x: 0, y: 0, width: side, height: side)
        panel.hostLayer?.addSublayer(constellation)
        if let view = panel.contentView {
            driver = DisplayLinkDriver(view: view) { [weak self] dt in self?.step(dt) }
        }
    }

    var isVisible: Bool { panel.isVisible }

    /// N1: the first frame is drawn before the panel is ordered in, so the card is
    /// complete on the very frame it appears.
    func show(on screen: CGRect) {
        panel.setFrame(DisplayPlacement.cardFrame(on: screen), display: false)
        constellation.contentsScale = panel.screen?.backingScaleFactor ?? 2
        level = 0
        simulation.show()
        constellation.update(simulation.step(dt: 0, level: 0))
        panel.orderFrontRegardless()
        driver?.start()
    }

    func set(mode: OverlayMode) {
        guard panel.isVisible else { return }
        simulation.set(mode: mode)
    }

    func setLevel(_ rms: Float) {
        level = Double(rms)
    }

    func hide() {
        driver?.stop()
        panel.orderOut(nil)
    }

    private func step(_ dt: TimeInterval) {
        constellation.update(simulation.step(dt: dt, level: level))
        if simulation.isFinished { hide() }
    }
}
