import Foundation

/// One frame of a new style: the sampler's marks plus everything the choreography drives.
/// `geometry` is the simulation's live buffer, handed over without a copy — draw from it
/// and let it go, as `ConstellationSimulation` hands over its `Frame` (design §5.6, R17).
public struct StyleFrame: Sendable {
    public internal(set) var geometry: StyleGeometry
    public internal(set) var cardAlpha: Double
    /// Horizontal shake offset applied to the whole card (error mode).
    public internal(set) var offsetX: Double
    public internal(set) var label: String
    public internal(set) var errorText: String
    public internal(set) var contentVisible: Bool
    /// 0→1 over `styleCheckSeconds` while the result's completion mark draws in.
    public internal(set) var checkProgress: Double
    public internal(set) var phase: StylePhase
}

/// Drives one of the five new styles: the shared `Choreography`, the app's `LevelSmoother`
/// and the mockup's 9 s⁻¹ geometry blend, with no AppKit and no drawing (design §5.6).
/// Deterministic for a given step sequence.
public struct StyleSimulation {
    private let style: OverlayStyle
    private let reduceMotion: Bool
    private var choreography: Choreography
    private var smoother = LevelSmoother()
    /// Two buffers, allocated once: the sampler's target and the blended geometry drawn.
    private var target = StyleGeometry()
    private var current = StyleGeometry()
    /// Free-running clock behind the motion; never reset, so the drift is continuous.
    private var time: TimeInterval = 0
    private var currentLevel = 0.0

    public init(style: OverlayStyle, reduceMotion: Bool = false) {
        self.style = style
        self.reduceMotion = reduceMotion
        choreography = Choreography(reduceMotion: reduceMotion)
    }

    /// The 0–1 level the style's marks are scaled by.
    public var level: Double { currentLevel }
    /// True once the current mode's choreography has run out and the panel should hide.
    public var isFinished: Bool { choreography.isFinished }

    public mutating func show() {
        choreography.show()
        smoother.reset()
        currentLevel = 0
        // Nothing to blend from, so the first frame snaps to its sample.
        current.count = 0
    }

    public mutating func set(mode: OverlayMode) {
        choreography.set(mode: mode)
    }

    /// Advances by `dt` seconds (clamped as `_tick` clamps it) and returns the frame to
    /// draw. `level` is the raw per-buffer RMS.
    public mutating func step(dt: TimeInterval, level: Double) -> StyleFrame {
        let dt = min(max(dt, 0), Constants.maxTimestep)
        time += dt
        choreography.advance(dt: dt)
        updateLevel(level)

        let phase = StylePhase(choreography.mode)
        if phase != .done {
            StyleSampler.sample(
                style,
                time: reduceMotion ? Constants.reduceMotionSampleTime : time,
                level: currentLevel,
                phase: phase,
                into: &target
            )
            blend(dt: dt)
        }

        return StyleFrame(
            geometry: current,
            cardAlpha: choreography.cardAlpha,
            offsetX: choreography.shakeOffset,
            label: choreography.label,
            errorText: choreography.errorText,
            contentVisible: choreography.contentVisible,
            checkProgress: checkProgress(phase: phase),
            phase: phase
        )
    }

    private mutating func updateLevel(_ raw: Double) {
        guard case .recording = choreography.mode else { return }
        currentLevel = reduceMotion
            ? ConstellationSimulation.normalisedLevel(rms: raw)
            : smoother.update(rms: raw)
    }

    /// The mockup's `1-Math.exp(-dt*9)` glide. A snap — Reduce Motion, or a point count
    /// that just changed, so there is nothing meaningful to glide from.
    private mutating func blend(dt: TimeInterval) {
        let rate = reduceMotion || current.count != target.count
            ? 1
            : 1 - exp(-Constants.styleBlendRate * dt)
        for index in 0..<target.count {
            current.points[index] = Self.blended(current.points[index], target.points[index], rate)
        }
        current.glowX = Self.blended(current.glowX, target.glowX, rate)
        current.count = target.count
    }

    /// A snap has to assign rather than interpolate: `from + (to - from)` is not exactly
    /// `to` in binary floating point, and Reduce Motion asserts an exact sample.
    private static func blended(_ from: Double, _ to: Double, _ rate: Double) -> Double {
        rate < 1 ? from + (to - from) * rate : to
    }

    private static func blended(_ from: StylePoint, _ to: StylePoint, _ rate: Double) -> StylePoint {
        StylePoint(
            x: blended(from.x, to.x, rate),
            y: blended(from.y, to.y, rate),
            alpha: blended(from.alpha, to.alpha, rate),
            height: blended(from.height, to.height, rate)
        )
    }

    private func checkProgress(phase: StylePhase) -> Double {
        guard phase == .done else { return 0 }
        guard !reduceMotion else { return 1 }
        return min(choreography.modeTime / Constants.styleCheckSeconds, 1)
    }
}
