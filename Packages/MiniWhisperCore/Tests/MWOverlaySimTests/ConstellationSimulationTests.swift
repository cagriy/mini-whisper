import Foundation
import Testing

import MWOverlaySim

/// The overlay's physics and choreography (design §5.6), a port of `_tick`, the seeding and
/// the constants of `../mini-whisper/src/mini_whisper/overlay.py` plus the accepted
/// Breathing mockup. Everything is deterministic under an injected seed; nothing draws.
@Suite struct ConstellationSimulationTests {
    private static let centre = Constants.windowSize / 2

    private func makeSimulation(seed: UInt64 = 42, reduceMotion: Bool = false)
        -> ConstellationSimulation
    {
        ConstellationSimulation(rng: SeededRandom(seed: seed), reduceMotion: reduceMotion)
    }

    /// The seeded constellation, observed by letting reduce-motion place the dots on their
    /// homes and taking a zero-length step.
    private func seededFrame(seed: UInt64 = 42) -> Frame {
        var simulation = makeSimulation(seed: seed, reduceMotion: true)
        simulation.show()
        return simulation.step(dt: 0, level: 0)
    }

    private func radius(_ dot: DotState) -> Double {
        hypot(dot.x - Self.centre, dot.y - Self.centre)
    }

    private func angle(_ dot: DotState) -> Double {
        let value = atan2(dot.y - Self.centre, dot.x - Self.centre)
        return value < 0 ? value + 2 * .pi : value
    }

    private func run(
        _ simulation: inout ConstellationSimulation,
        seconds: TimeInterval,
        level: Double = 0,
        step dt: TimeInterval = 1.0 / 60
    ) -> Frame {
        var frame = simulation.step(dt: 0, level: level)
        var elapsed = 0.0
        while elapsed < seconds {
            frame = simulation.step(dt: dt, level: level)
            elapsed += dt
        }
        return frame
    }

    // MARK: - Seeding

    @Test func seeds24DotsTenOnRingWithinJitter() {
        let frame = seededFrame()

        #expect(frame.dots.count == 24)
        let slot = 2 * Double.pi / Double(Constants.ringDotCount)
        for index in 0..<Constants.ringDotCount {
            let dot = frame.dots[index]
            #expect(abs(radius(dot) - Constants.dotAreaRadius) <= Constants.dotAreaRadius * Constants.ringRadialJitter + 1e-9)
            var offset = angle(dot) - Double(index) * slot
            if offset > .pi { offset -= 2 * .pi }
            if offset < -.pi { offset += 2 * .pi }
            #expect(abs(offset) <= Constants.ringAngularJitter * slot + 1e-9)
        }
    }

    @Test func remaining14InsideDisc() {
        let frame = seededFrame()

        for dot in frame.dots.dropFirst(Constants.ringDotCount) {
            #expect(radius(dot) <= Constants.dotAreaRadius + 1e-9)
        }
    }

    @Test func dotRadiiBetween2And5() {
        let frame = seededFrame()

        #expect(frame.dots.allSatisfy {
            $0.radius >= Constants.dotRadiusMin && $0.radius <= Constants.dotRadiusMax
        })
    }

    // MARK: - show()

    @Test func showPlacesDotsAtCentreWithZeroVelocity() {
        var simulation = makeSimulation()
        simulation.show()

        let frame = simulation.step(dt: 0, level: 0)

        #expect(frame.dots.allSatisfy { $0.x == Self.centre && $0.y == Self.centre })
    }

    @Test func showFadesCardIn120ms() {
        var simulation = makeSimulation()
        simulation.show()

        // Steps are clamped to `maxTimestep`, so 120 ms takes four 30 ms frames.
        #expect(simulation.step(dt: 0, level: 0).cardAlpha == 0)
        #expect(abs(simulation.step(dt: 0.03, level: 0).cardAlpha - 0.25) < 1e-9)
        #expect(abs(simulation.step(dt: 0.03, level: 0).cardAlpha - 0.5) < 1e-9)
        #expect(abs(simulation.step(dt: 0.03, level: 0).cardAlpha - 0.75) < 1e-9)
        #expect(simulation.step(dt: 0.03, level: 0).cardAlpha == 1)
        #expect(simulation.step(dt: 0.05, level: 0).cardAlpha == 1)
    }

    // MARK: - Modes

    @Test func startingHomesBreathe() {
        #expect(ConstellationSimulation.breathingRadius(at: 0) == Constants.breathingRingRadius)
        #expect(abs(ConstellationSimulation.breathingRadius(at: 0.25)
            - (Constants.breathingRingRadius + Constants.breathingRingAmplitude)) < 1e-9)
        #expect(abs(ConstellationSimulation.breathingRadius(at: 0.75)
            - (Constants.breathingRingRadius - Constants.breathingRingAmplitude)) < 1e-9)
        #expect(abs(ConstellationSimulation.breathingRadius(at: 1)
            - Constants.breathingRingRadius) < 1e-9)

        var simulation = makeSimulation()
        simulation.show()
        let frame = run(&simulation, seconds: 2)

        let bound = Constants.breathingRingRadius + Constants.breathingRingAmplitude
            + Constants.ambientAmplitude + 5
        #expect(frame.dots.allSatisfy { radius($0) <= bound })
    }

    @Test func recordingConvergesToSeededHomesWithoutAudio() {
        var simulation = makeSimulation()
        simulation.show()
        simulation.set(mode: .recording)

        let frame = run(&simulation, seconds: 3)

        let slack = Constants.ambientAmplitude + 1
        for index in 0..<Constants.ringDotCount {
            let distance = radius(frame.dots[index])
            let jitter = Constants.dotAreaRadius * Constants.ringRadialJitter
            #expect(distance >= Constants.dotAreaRadius - jitter - slack)
            #expect(distance <= Constants.dotAreaRadius + jitter + slack)
        }
    }

    @Test func audioLevelMapping() {
        #expect(ConstellationSimulation.normalisedLevel(rms: Constants.levelFloor) == 0)
        #expect(ConstellationSimulation.normalisedLevel(rms: 0) == 0)
        #expect(ConstellationSimulation.normalisedLevel(rms: Constants.levelCeil) == 1)
        #expect(ConstellationSimulation.normalisedLevel(rms: 1) == 1)

        var simulation = makeSimulation()
        simulation.show()
        simulation.set(mode: .recording)

        _ = simulation.step(dt: 1.0 / 60, level: Constants.levelCeil)
        #expect(abs(simulation.level - Constants.smoothAttack) < 1e-9)
        _ = simulation.step(dt: 1.0 / 60, level: Constants.levelCeil)
        #expect(abs(simulation.level - 0.84) < 1e-9)
        _ = simulation.step(dt: 1.0 / 60, level: 0)
        #expect(abs(simulation.level - 0.84 * (1 - Constants.smoothDecay)) < 1e-9)
    }

    @Test func audioDisplacementScales130() {
        let full = ConstellationSimulation.audioDisplacement(level: 1, angle: 0)
        #expect(abs(full.x - Constants.audioAmplitude) < 1e-9)
        #expect(abs(full.y) < 1e-9)

        let half = ConstellationSimulation.audioDisplacement(level: 0.5, angle: .pi / 2)
        #expect(abs(half.x) < 1e-9)
        #expect(abs(half.y - Constants.audioAmplitude / 2) < 1e-9)
    }

    @Test func processingRotatesHomesAt3RadPerSecond() {
        var simulation = makeSimulation()
        simulation.show()
        simulation.set(mode: .processing)

        for _ in 0..<20 { _ = simulation.step(dt: 0.05, level: 0) }

        #expect(abs(simulation.rotation - Constants.processingRotationSpeed) < 1e-9)
    }

    @Test func resultCollapsesToCentreThenFadesOut() {
        var simulation = makeSimulation()
        simulation.show()
        _ = run(&simulation, seconds: 0.5)
        simulation.set(mode: .result)

        var frame = run(&simulation, seconds: Constants.resultHoldSeconds, step: 0.01)
        #expect(abs(frame.cardAlpha - 1) < 1e-9)
        #expect(!simulation.isFinished)

        frame = run(&simulation, seconds: Constants.cardFadeSeconds / 2, step: 0.03)
        #expect(abs(frame.cardAlpha - 0.5) < 1e-9)

        frame = run(&simulation, seconds: 0.2, step: 0.03)
        #expect(frame.cardAlpha == 0)
        #expect(simulation.isFinished)
        #expect(frame.dots.allSatisfy { hypot($0.x - Self.centre, $0.y - Self.centre) < 30 })
    }

    @Test func errorShakeProfileAndDuration() {
        var simulation = makeSimulation()
        simulation.show()
        simulation.set(mode: .error("boom"))

        // 60·t = π/2, so the sine is at its peak and only the envelope remains.
        let peak = Double.pi / 120
        let frame = simulation.step(dt: peak, level: 0)
        let expected = Constants.shakeAmplitude * (1 - peak / Constants.shakeDuration)
        #expect(abs(frame.offsetX - expected) < 1e-9)
        #expect(frame.errorText == "boom")

        let settled = run(&simulation, seconds: Constants.shakeDuration, step: 0.01)
        #expect(settled.offsetX == 0)
        #expect(!settled.dotsVisible)
    }

    @Test func errorHidesAfter3s() {
        var simulation = makeSimulation()
        simulation.show()
        simulation.set(mode: .error("boom"))

        _ = run(&simulation, seconds: Constants.errorSeconds - 0.2, step: 0.01)
        #expect(!simulation.isFinished)

        _ = run(&simulation, seconds: 0.3, step: 0.01)
        #expect(simulation.isFinished)
    }

    // MARK: - Links

    @Test func linksUnder120ptWithAlphaFormula() {
        var simulation = makeSimulation()
        simulation.show()
        simulation.set(mode: .recording)
        let frame = run(&simulation, seconds: 1)

        #expect(frame.linkCount > 0)
        for link in frame.links.prefix(frame.linkCount) {
            let a = frame.dots[link.a]
            let b = frame.dots[link.b]
            let distance = hypot(a.x - b.x, a.y - b.y)
            #expect(distance < Constants.connectionDistance)
            let expected = (1 - distance / Constants.connectionDistance) * Constants.linkAlphaScale
            #expect(abs(link.alpha - expected) < 1e-9)
        }
    }

    @Test func maxLinksIs276() {
        #expect(Constants.maxLinks == 276)

        var simulation = makeSimulation()
        simulation.show()
        let frame = simulation.step(dt: 0, level: 0)

        // Every dot starts at the centre, so every pair is inside the connection distance.
        #expect(frame.linkCount == Constants.maxLinks)
    }

    // MARK: - Robustness and labels

    @Test func dtClampedTo50msNoNaN() {
        var lagging = makeSimulation(seed: 7)
        lagging.show()
        lagging.set(mode: .recording)
        var capped = makeSimulation(seed: 7)
        capped.show()
        capped.set(mode: .recording)

        let spike = lagging.step(dt: 5, level: Constants.levelCeil)
        let limit = capped.step(dt: Constants.maxTimestep, level: Constants.levelCeil)

        #expect(spike.dots == limit.dots)
        #expect(spike.dots.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test func labelStrings() {
        var simulation = makeSimulation()
        simulation.show()
        #expect(simulation.step(dt: 0, level: 0).label == "starting…")

        simulation.set(mode: .recording)
        let recording = run(&simulation, seconds: 1.5, step: 0.05)
        #expect(recording.label == "1.5s")

        simulation.set(mode: .processing)
        #expect(simulation.step(dt: 0.05, level: 0).label == "processing...")
    }

    @Test func reduceMotionSkipsSpringFromCentreAndShake() {
        var simulation = makeSimulation(reduceMotion: true)
        simulation.show()

        let start = simulation.step(dt: 0, level: 0)
        #expect(start.dots.contains { hypot($0.x - Self.centre, $0.y - Self.centre) > 1 })

        simulation.set(mode: .error("boom"))
        for _ in 0..<10 {
            #expect(simulation.step(dt: 0.01, level: 0).offsetX == 0)
        }
    }

    @Test func frameHasFixedCapacity() {
        var simulation = makeSimulation()
        simulation.show()
        let first = simulation.step(dt: 0, level: 0)
        #expect(first.dots.count == Constants.dotCount)
        #expect(first.links.count == Constants.maxLinks)

        simulation.set(mode: .recording)
        let later = run(&simulation, seconds: 2, level: Constants.levelCeil)
        #expect(later.dots.count == Constants.dotCount)
        #expect(later.links.count == Constants.maxLinks)

        simulation.show()
        let reshown = simulation.step(dt: 0, level: 0)
        #expect(reshown.dots.count == Constants.dotCount)
        #expect(reshown.links.count == Constants.maxLinks)
    }
}
