import AppKit
import MWOverlaySim
import QuartzCore

private let cardBounds = CGRect(
    x: 0, y: 0, width: Constants.windowSize, height: Constants.windowSize
)

/// One overlay style as a simulation and a layer, driven by `dt` and a raw level. The
/// single seam the card and the Settings preview share, so the two cannot drift apart
/// (design §5.1, §5.6).
@MainActor
protocol OverlayAnimator: AnyObject {
    var style: OverlayStyle { get }
    var layer: CALayer { get }
    /// True once the current mode's choreography has run out and the host should hide.
    var isFinished: Bool { get }
    func show()
    func set(mode: OverlayMode)
    func step(dt: TimeInterval, level: Double)
    func setContentsScale(_ scale: CGFloat)
}

@MainActor
final class ConstellationAnimator: OverlayAnimator {
    let style = OverlayStyle.constellation
    private let constellation = ConstellationLayer()
    private var simulation: ConstellationSimulation

    init(reduceMotion: Bool) {
        simulation = ConstellationSimulation(reduceMotion: reduceMotion)
        constellation.frame = cardBounds
    }

    var layer: CALayer { constellation }
    var isFinished: Bool { simulation.isFinished }

    func show() { simulation.show() }
    func set(mode: OverlayMode) { simulation.set(mode: mode) }

    func step(dt: TimeInterval, level: Double) {
        constellation.update(simulation.step(dt: dt, level: level))
    }

    func setContentsScale(_ scale: CGFloat) { constellation.contentsScale = scale }
}

@MainActor
final class StyleAnimator: OverlayAnimator {
    let style: OverlayStyle
    private let marks: StyleLayer
    private var simulation: StyleSimulation

    init(style: OverlayStyle, reduceMotion: Bool) {
        self.style = style
        simulation = StyleSimulation(style: style, reduceMotion: reduceMotion)
        marks = StyleLayer(style: style)
        marks.frame = cardBounds
    }

    var layer: CALayer { marks }
    var isFinished: Bool { simulation.isFinished }

    func show() { simulation.show() }
    func set(mode: OverlayMode) { simulation.set(mode: mode) }

    func step(dt: TimeInterval, level: Double) {
        marks.update(simulation.step(dt: dt, level: level))
    }

    func setContentsScale(_ scale: CGFloat) { marks.contentsScale = scale }
}

@MainActor
enum OverlayAnimatorFactory {
    static func make(style: OverlayStyle, reduceMotion: Bool) -> any OverlayAnimator {
        guard style != .constellation else {
            return ConstellationAnimator(reduceMotion: reduceMotion)
        }
        return StyleAnimator(style: style, reduceMotion: reduceMotion)
    }
}
