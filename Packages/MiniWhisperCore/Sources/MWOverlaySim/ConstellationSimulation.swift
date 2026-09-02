import Foundation

/// The overlay's physics and choreography, with no AppKit and no drawing: a port of
/// `overlay.py`'s `_tick` and seeding, extended with the Breathing choreography of design
/// §5.6. Deterministic for a given seed and step sequence.
public struct ConstellationSimulation {
    private struct Dot {
        var homeX = 0.0
        var homeY = 0.0
        /// Direction of the home from the centre, reused by the breathing ring so the
        /// expansion into the constellation is radial.
        var homeAngle = 0.0
        var x = 0.0
        var y = 0.0
        var vx = 0.0
        var vy = 0.0
        var radius = 0.0
        var phase = 0.0
        var audioAngle = 0.0
    }

    private static let centre = Constants.windowSize / 2

    private var rng: SeededRandom
    private let reduceMotion: Bool
    private var dots: [Dot]
    private var frame: Frame
    private var mode: OverlayMode = .starting
    /// Free-running clock behind the ambient orbit; never reset, so the drift is continuous.
    private var time: TimeInterval = 0
    private var modeTime: TimeInterval = 0
    private var showTime: TimeInterval = 0
    private var smoothedLevel = 0.0
    private var rotationAngle = 0.0

    public init(rng: SeededRandom = SeededRandom(), reduceMotion: Bool = false) {
        self.rng = rng
        self.reduceMotion = reduceMotion
        dots = Array(repeating: Dot(), count: Constants.dotCount)
        frame = Frame(dotCount: Constants.dotCount, linkCapacity: Constants.maxLinks)
    }

    // MARK: - Observable state

    /// The smoothed 0–1 audio level the displacement is scaled by.
    public var level: Double { smoothedLevel }
    /// Radians the processing constellation has turned through.
    public var rotation: Double { rotationAngle }
    /// True once the current mode's choreography has run out and the panel should hide.
    public var isFinished: Bool {
        switch mode {
        case .result: modeTime >= Constants.resultHoldSeconds + Constants.cardFadeSeconds
        case .error: modeTime >= Constants.errorSeconds
        case .starting, .recording, .processing: false
        }
    }

    // MARK: - Pure mappings

    /// Design §5.6: the starting ring breathes between 24 and 36 pt once a second.
    public static func breathingRadius(at time: TimeInterval) -> Double {
        Constants.breathingRingRadius
            + Constants.breathingRingAmplitude
            * sin(2 * .pi * time / Constants.breathingPeriod)
    }

    /// `overlay.py:_tick` — raw RMS mapped onto 0–1 between the floor and the ceiling.
    public static func normalisedLevel(rms: Double) -> Double {
        let span = Constants.levelCeil - Constants.levelFloor
        return min(max((rms - Constants.levelFloor) / span, 0), 1)
    }

    public static func audioDisplacement(level: Double, angle: Double) -> (x: Double, y: Double) {
        (level * Constants.audioAmplitude * cos(angle),
         level * Constants.audioAmplitude * sin(angle))
    }

    /// The error card's horizontal shake: a 60 rad/s oscillation inside a linear envelope.
    public static func shakeOffset(at time: TimeInterval) -> Double {
        guard time < Constants.shakeDuration else { return 0 }
        return Constants.shakeAmplitude
            * sin(Constants.shakeFrequency * time)
            * (1 - time / Constants.shakeDuration)
    }

    // MARK: - Lifecycle

    /// Reseeds the constellation and starts the show choreography: every dot at the centre
    /// with no velocity, the card fading in over 120 ms (design §5.6).
    public mutating func show() {
        mode = .starting
        modeTime = 0
        showTime = 0
        smoothedLevel = 0
        rotationAngle = 0
        frame.errorText = ""
        frame.offsetX = 0
        frame.cardAlpha = 0
        frame.dotsVisible = true

        for index in dots.indices {
            let (x, y) = seedPosition(index: index)
            dots[index].homeX = x
            dots[index].homeY = y
            dots[index].homeAngle = atan2(y - Self.centre, x - Self.centre)
            // Reduce motion skips the spring from the centre; the dots simply appear.
            dots[index].x = reduceMotion ? x : Self.centre
            dots[index].y = reduceMotion ? y : Self.centre
            dots[index].vx = 0
            dots[index].vy = 0
            dots[index].radius = rng.uniform(Constants.dotRadiusMin, Constants.dotRadiusMax)
            dots[index].phase = rng.uniform(0, 2 * .pi)
            dots[index].audioAngle = rng.uniform(0, 2 * .pi)
        }
    }

    public mutating func set(mode: OverlayMode) {
        self.mode = mode
        modeTime = 0
        if case .processing = mode { rotationAngle = 0 }
        if case .error(let message) = mode {
            frame.errorText = message
        } else {
            frame.errorText = ""
            frame.offsetX = 0
        }
    }

    // MARK: - Step

    /// Advances the simulation by `dt` seconds (clamped, as `_tick` does) and returns the
    /// frame to draw. `level` is the raw per-buffer RMS.
    public mutating func step(dt: TimeInterval, level: Double) -> Frame {
        let dt = min(max(dt, 0), Constants.maxTimestep)
        time += dt
        modeTime += dt
        showTime += dt

        updateLevel(level)
        integrate(dt: dt)
        computeLinks()

        frame.cardAlpha = cardAlpha()
        frame.offsetX = shake()
        frame.dotsVisible = dotsVisible()
        frame.label = label()
        for index in dots.indices {
            frame.dots[index] = DotState(x: dots[index].x, y: dots[index].y, radius: dots[index].radius)
        }
        return frame
    }

    // MARK: - Physics

    private mutating func updateLevel(_ raw: Double) {
        guard case .recording = mode else { return }
        let normalised = Self.normalisedLevel(rms: raw)
        // The one-pole is per tick, not per second — the same frame-rate coupling the
        // source has, kept for visual parity.
        let coefficient = normalised > smoothedLevel ? Constants.smoothAttack : Constants.smoothDecay
        smoothedLevel += coefficient * (normalised - smoothedLevel)
    }

    private mutating func integrate(dt: TimeInterval) {
        if case .processing = mode {
            rotationAngle += Constants.processingRotationSpeed * dt
        }
        let cosine = cos(rotationAngle)
        let sine = sin(rotationAngle)

        for index in dots.indices {
            var dot = dots[index]
            let (baseX, baseY) = home(dot, cosine: cosine, sine: sine)

            let orbit = time * Constants.ambientSpeed + dot.phase
            var targetX = baseX + Constants.ambientAmplitude * cos(orbit)
            var targetY = baseY + Constants.ambientAmplitude * sin(orbit)

            if case .recording = mode {
                dot.audioAngle += rng.gaussian() * Constants.audioAngleDrift
                    * (1 + smoothedLevel * Constants.audioAngleBoost) * dt
                let audio = Self.audioDisplacement(level: smoothedLevel, angle: dot.audioAngle)
                targetX += audio.x
                targetY += audio.y
            }

            let forceX = Constants.springK * (targetX - dot.x) - Constants.damping * dot.vx
            let forceY = Constants.springK * (targetY - dot.y) - Constants.damping * dot.vy
            dot.vx += forceX * dt
            dot.vy += forceY * dt
            dot.x += dot.vx * dt
            dot.y += dot.vy * dt
            dots[index] = dot
        }
    }

    /// Where a dot is pulled towards, before ambient drift — the mode's whole choreography.
    private func home(_ dot: Dot, cosine: Double, sine: Double) -> (Double, Double) {
        switch mode {
        case .starting:
            let radius = Self.breathingRadius(at: time)
            return (Self.centre + radius * cos(dot.homeAngle),
                    Self.centre + radius * sin(dot.homeAngle))
        case .result:
            return (Self.centre, Self.centre)
        case .processing:
            let dx = dot.homeX - Self.centre
            let dy = dot.homeY - Self.centre
            return (Self.centre + dx * cosine - dy * sine,
                    Self.centre + dx * sine + dy * cosine)
        case .recording, .error:
            return (dot.homeX, dot.homeY)
        }
    }

    private mutating func computeLinks() {
        var count = 0
        for i in 0..<dots.count {
            for j in (i + 1)..<dots.count {
                let distance = hypot(dots[i].x - dots[j].x, dots[i].y - dots[j].y)
                guard distance < Constants.connectionDistance else { continue }
                frame.links[count] = Link(
                    a: i,
                    b: j,
                    alpha: (1 - distance / Constants.connectionDistance) * Constants.linkAlphaScale
                )
                count += 1
            }
        }
        frame.linkCount = count
    }

    // MARK: - Choreography

    private func cardAlpha() -> Double {
        let fadeIn = min(showTime / Constants.cardFadeSeconds, 1)
        guard case .result = mode else { return fadeIn }
        let fadeOut = (modeTime - Constants.resultHoldSeconds) / Constants.cardFadeSeconds
        return min(fadeIn, 1 - min(max(fadeOut, 0), 1))
    }

    private func shake() -> Double {
        guard case .error = mode, !reduceMotion else { return 0 }
        return Self.shakeOffset(at: modeTime)
    }

    private func dotsVisible() -> Bool {
        guard case .error = mode else { return true }
        // Once the shake is spent the message takes the card over (design §5.6).
        return modeTime < Constants.shakeDuration
    }

    private func label() -> String {
        switch mode {
        case .starting: Constants.startingLabel
        case .processing: Constants.processingLabel
        case .recording: String(format: "%.1fs", showTime)
        case .result, .error: ""
        }
    }

    // MARK: - Seeding

    /// `overlay.py:_random_dot_position`: the first ten dots on the ring inside their
    /// angular slot, the rest uniform over the disc.
    private mutating func seedPosition(index: Int) -> (Double, Double) {
        let angle: Double
        let distance: Double
        if index < Constants.ringDotCount {
            let slot = 2 * Double.pi / Double(Constants.ringDotCount)
            let jitter = rng.uniform(-Constants.ringAngularJitter, Constants.ringAngularJitter)
            angle = Double(index) * slot + jitter * slot
            distance = Constants.dotAreaRadius
                * (1 + rng.uniform(-Constants.ringRadialJitter, Constants.ringRadialJitter))
        } else {
            angle = rng.uniform(0, 2 * .pi)
            distance = Constants.dotAreaRadius * rng.unit().squareRoot()
        }
        return (Self.centre + distance * cos(angle), Self.centre + distance * sin(angle))
    }
}
