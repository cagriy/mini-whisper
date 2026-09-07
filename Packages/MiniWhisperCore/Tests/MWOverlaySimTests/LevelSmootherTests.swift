import Testing

import MWOverlaySim

/// The attack/decay one-pole `ConstellationSimulationTests.audioLevelMapping` pins, on its
/// own value now that every style shares one envelope (design §3 R7).
@Suite struct LevelSmootherTests {
    @Test func attackAndDecayMatchTheShippedOnePole() {
        var smoother = LevelSmoother()

        #expect(abs(smoother.update(rms: Constants.levelCeil) - Constants.smoothAttack) < 1e-9)
        #expect(abs(smoother.update(rms: Constants.levelCeil) - 0.84) < 1e-9)

        let decayed = smoother.update(rms: 0)
        #expect(abs(decayed - 0.84 * (1 - Constants.smoothDecay)) < 1e-9)
        #expect(smoother.level == decayed)
    }

    @Test func resetReturnsToZero() {
        var smoother = LevelSmoother()
        _ = smoother.update(rms: Constants.levelCeil)
        #expect(smoother.level > 0)

        smoother.reset()
        #expect(smoother.level == 0)
    }
}
