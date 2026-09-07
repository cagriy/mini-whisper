import Foundation
import Testing

import MWOverlaySim

/// The stateful driver behind a new style: the shared choreography, the app's level
/// one-pole, the 9 s⁻¹ geometry blend and Reduce Motion (design §5.6, §5.12). Every
/// duration is injected `dt`; nothing here sleeps.
private let newStyles: [OverlayStyle] = [
    .silkRibbon, .resonantHalo, .softMeter, .liquidPearl, .petalIris,
]

private let tick = 1.0 / 60

private func live(_ geometry: StyleGeometry) -> [StylePoint] {
    Array(geometry.points.prefix(geometry.count))
}

@Suite struct StyleSimulationTests {
    private func started(
        _ style: OverlayStyle = .softMeter,
        reduceMotion: Bool = false
    ) -> StyleSimulation {
        var simulation = StyleSimulation(style: style, reduceMotion: reduceMotion)
        simulation.show()
        return simulation
    }

    @discardableResult
    private func run(
        _ simulation: inout StyleSimulation,
        steps: Int,
        level: Double = 0,
        dt: TimeInterval = tick
    ) -> StyleFrame {
        var frame = simulation.step(dt: dt, level: level)
        for _ in 1..<max(steps, 1) { frame = simulation.step(dt: dt, level: level) }
        return frame
    }

    /// Reads the live geometry's storage address without keeping the frame alive, so the
    /// simulation's buffer stays uniquely referenced between steps (R17).
    private func bufferIdentity(_ simulation: inout StyleSimulation) -> UnsafeRawPointer? {
        simulation.step(dt: tick, level: 0).geometry.points
            .withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
    }

    // MARK: - Phase and level

    @Test func modeMapsToPhase() {
        var simulation = started()
        #expect(simulation.step(dt: tick, level: 0).phase == .quiet)

        for (mode, phase) in [
            (OverlayMode.recording, StylePhase.speaking),
            (.processing, .processing),
            (.result, .done),
            (.error("boom"), .quiet),
        ] {
            simulation.set(mode: mode)
            #expect(simulation.step(dt: tick, level: 0).phase == phase)
        }
    }

    @Test func levelMatchesLevelSmoother() {
        var simulation = started()
        simulation.set(mode: .recording)

        _ = simulation.step(dt: tick, level: Constants.levelCeil)
        #expect(abs(simulation.level - Constants.smoothAttack) < 1e-9)
        _ = simulation.step(dt: tick, level: Constants.levelCeil)
        #expect(abs(simulation.level - 0.84) < 1e-9)
        _ = simulation.step(dt: tick, level: 0)
        let decayed = 0.84 * (1 - Constants.smoothDecay)
        #expect(abs(simulation.level - decayed) < 1e-9)

        simulation.set(mode: .processing)
        _ = simulation.step(dt: tick, level: Constants.levelCeil)
        #expect(abs(simulation.level - decayed) < 1e-9)
    }

    // MARK: - Blend

    /// Soft meter's quiet form is time-invariant, so a run against it pins the one-pole
    /// exactly: after a second the remaining gap is `e^-9` of the gap it started with.
    @Test func blendFollowsTheNinePerSecondOnePole() {
        var simulation = started()
        simulation.set(mode: .recording)
        let start = run(&simulation, steps: 60, level: Constants.levelCeil).geometry

        simulation.set(mode: .starting)
        let after = run(&simulation, steps: 60).geometry

        var target = StyleGeometry()
        StyleSampler.sample(.softMeter, time: 0, level: 0, phase: .quiet, into: &target)
        let residual = exp(-Constants.styleBlendRate)
        for index in 0..<target.count {
            let expected = target.points[index].height
                + (start.points[index].height - target.points[index].height) * residual
            #expect(abs(after.points[index].height - expected) < 1e-9)
        }
    }

    @Test(arguments: newStyles) func modeChangeGlidesRatherThanJumps(_ style: OverlayStyle) {
        var simulation = started(style)
        simulation.set(mode: .recording)
        let before = run(&simulation, steps: 60, level: Constants.levelCeil).geometry

        simulation.set(mode: .processing)
        let after = simulation.step(dt: tick, level: Constants.levelCeil).geometry

        var target = StyleGeometry()
        StyleSampler.sample(style, time: 61 * tick, level: 0, phase: .processing, into: &target)

        var glided = 0
        for index in 0..<target.count {
            for component in [\StylePoint.x, \.y, \.alpha, \.height] {
                let from = before.points[index][keyPath: component]
                let to = target.points[index][keyPath: component]
                guard abs(to - from) > 1e-6 else { continue }
                let moved = after.points[index][keyPath: component]
                #expect(min(from, to) < moved)
                #expect(moved < max(from, to))
                glided += 1
            }
        }
        #expect(glided > 0)
    }

    // MARK: - Completion mark

    @Test func checkProgressRampsOver350ms() {
        var simulation = started()
        #expect(simulation.step(dt: tick, level: 0).checkProgress == 0)
        simulation.set(mode: .processing)
        #expect(simulation.step(dt: tick, level: 0).checkProgress == 0)

        simulation.set(mode: .result)
        #expect(simulation.step(dt: 0, level: 0).checkProgress == 0)
        var frame = run(&simulation, steps: 5, dt: Constants.styleCheckSeconds / 10)
        #expect(abs(frame.checkProgress - 0.5) < 1e-9)
        frame = run(&simulation, steps: 5, dt: Constants.styleCheckSeconds / 10)
        #expect(abs(frame.checkProgress - 1) < 1e-9)
        frame = run(&simulation, steps: 5, dt: Constants.styleCheckSeconds / 10)
        #expect(frame.checkProgress == 1)
    }

    // MARK: - Reduce Motion

    @Test(arguments: newStyles) func reduceMotionFreezesTimeAndSnaps(_ style: OverlayStyle) {
        var simulation = started(style, reduceMotion: true)
        simulation.set(mode: .recording)
        let frame = run(&simulation, steps: 20, level: Constants.levelCeil)

        #expect(simulation.level == 1)
        var expected = StyleGeometry()
        StyleSampler.sample(
            style,
            time: Constants.reduceMotionSampleTime,
            level: 1,
            phase: .speaking,
            into: &expected
        )
        #expect(live(frame.geometry) == live(expected))
        #expect(frame.geometry.glowX == expected.glowX)

        simulation.set(mode: .result)
        #expect(simulation.step(dt: tick, level: 0).checkProgress == 1)
    }

    // MARK: - Clock

    @Test func dtIsClampedTo50ms() {
        var simulation = started()
        simulation.set(mode: .result)

        _ = simulation.step(dt: 10, level: 0)
        #expect(!simulation.isFinished)

        run(&simulation, steps: 7, dt: Constants.maxTimestep)
        #expect(simulation.isFinished)
    }

    /// The frame carries the shared choreography untouched — the same fade, shake and
    /// labels `ChoreographyTests` pins for the constellation.
    @Test func frameCarriesTheChoreography() {
        var simulation = started()
        var frame = run(&simulation, steps: 2, dt: Constants.cardFadeSeconds / 4)
        #expect(abs(frame.cardAlpha - 0.5) < 1e-9)
        #expect(frame.label == Constants.startingLabel)

        simulation.set(mode: .processing)
        #expect(simulation.step(dt: 0, level: 0).label == Constants.processingLabel)

        simulation.set(mode: .error("boom"))
        // 60·t = π/2, so the sine is at its peak and only the envelope remains.
        let peak = Double.pi / 120
        frame = simulation.step(dt: peak, level: 0)
        #expect(abs(frame.offsetX - ConstellationSimulation.shakeOffset(at: peak)) < 1e-9)
        #expect(frame.contentVisible)
    }

    @Test func isFinishedMatchesTheConstellation() {
        var simulation = started()
        simulation.set(mode: .result)
        run(&simulation, steps: 26, dt: 0.01)
        #expect(!simulation.isFinished)
        run(&simulation, steps: 15, dt: 0.01)
        #expect(simulation.isFinished)

        simulation.set(mode: .error("boom"))
        run(&simulation, steps: 280, dt: 0.01)
        #expect(!simulation.isFinished)
        run(&simulation, steps: 30, dt: 0.01)
        #expect(simulation.isFinished)

        let frame = simulation.step(dt: 0, level: 0)
        #expect(frame.errorText == "boom")
        #expect(!frame.contentVisible)
        #expect(frame.label.isEmpty)
    }

    // MARK: - Allocation

    @Test(arguments: newStyles) func geometryCapacityIsConstantAcrossShow(_ style: OverlayStyle) {
        var simulation = started(style)
        let expected = StyleSampler.pointCount(style)

        for mode in [OverlayMode.recording, .processing, .error("boom")] {
            simulation.set(mode: mode)
            let frame = run(&simulation, steps: 30, level: Constants.levelCeil)
            #expect(frame.geometry.points.count == Constants.stylePointCapacity)
            #expect(frame.geometry.count == expected)
        }

        simulation.show()
        let frame = run(&simulation, steps: 30)
        #expect(frame.geometry.points.count == Constants.stylePointCapacity)
        #expect(frame.geometry.count == expected)
    }

    @Test func geometryBufferIsAllocatedOnceAcrossAShow() {
        var simulation = started(.petalIris)
        let first = bufferIdentity(&simulation)
        #expect(first != nil)

        for (mode, steps) in [
            (OverlayMode.recording, 300), (.processing, 200), (.result, 100),
        ] {
            simulation.set(mode: mode)
            for _ in 0..<steps { _ = simulation.step(dt: tick, level: Constants.levelCeil) }
        }

        #expect(bufferIdentity(&simulation) == first)
    }
}
