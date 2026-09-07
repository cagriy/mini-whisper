import Foundation
import Testing

import MWOverlaySim

/// The mode clock and the card behaviour it drives, asserted on the same numbers
/// `ConstellationSimulationTests` pins so the extraction is behaviour-preserving
/// (design §5.12). Every duration is injected `dt`.
@Suite struct ChoreographyTests {
    private func advance(
        _ choreography: inout Choreography,
        seconds: TimeInterval,
        step dt: TimeInterval = 0.01
    ) {
        var elapsed = 0.0
        while elapsed < seconds {
            choreography.advance(dt: dt)
            elapsed += dt
        }
    }

    private func started(reduceMotion: Bool = false) -> Choreography {
        var choreography = Choreography(reduceMotion: reduceMotion)
        choreography.show()
        return choreography
    }

    @Test func showFadesCardIn120ms() {
        var choreography = started()

        #expect(choreography.cardAlpha == 0)
        for expected in [0.25, 0.5, 0.75] {
            choreography.advance(dt: 0.03)
            #expect(abs(choreography.cardAlpha - expected) < 1e-9)
        }
        choreography.advance(dt: 0.03)
        #expect(choreography.cardAlpha == 1)
        choreography.advance(dt: 0.05)
        #expect(choreography.cardAlpha == 1)
    }

    @Test func resultHoldsThenFadesOut() {
        var choreography = started()
        advance(&choreography, seconds: 0.5)
        choreography.set(mode: .result)

        advance(&choreography, seconds: Constants.resultHoldSeconds)
        #expect(abs(choreography.cardAlpha - 1) < 1e-9)
        #expect(!choreography.isFinished)

        advance(&choreography, seconds: Constants.cardFadeSeconds / 2, step: 0.03)
        #expect(abs(choreography.cardAlpha - 0.5) < 1e-9)

        advance(&choreography, seconds: 0.2, step: 0.03)
        #expect(choreography.cardAlpha == 0)
        #expect(choreography.isFinished)
    }

    @Test func errorShakeProfileAndDuration() {
        var choreography = started()
        choreography.set(mode: .error("boom"))
        #expect(choreography.errorText == "boom")

        // 60·t = π/2, so the sine is at its peak and only the envelope remains.
        let peak = Double.pi / 120
        choreography.advance(dt: peak)
        let expected = Constants.shakeAmplitude * (1 - peak / Constants.shakeDuration)
        #expect(abs(choreography.shakeOffset - expected) < 1e-9)

        advance(&choreography, seconds: Constants.shakeDuration)
        #expect(choreography.shakeOffset == 0)
    }

    @Test func contentHiddenAfterShake() {
        var choreography = started()
        choreography.set(mode: .error("boom"))

        advance(&choreography, seconds: Constants.shakeDuration - 0.02)
        #expect(choreography.contentVisible)

        advance(&choreography, seconds: 0.05)
        #expect(!choreography.contentVisible)
    }

    @Test func errorFinishesAt3s() {
        var choreography = started()
        choreography.set(mode: .error("boom"))

        advance(&choreography, seconds: Constants.errorSeconds - 0.2)
        #expect(!choreography.isFinished)

        advance(&choreography, seconds: 0.3)
        #expect(choreography.isFinished)
    }

    @Test func labelStrings() {
        var choreography = started()
        #expect(choreography.label == Constants.startingLabel)

        choreography.set(mode: .recording)
        advance(&choreography, seconds: 1.5, step: 0.05)
        #expect(choreography.label == String(format: "%.1fs", choreography.showTime))
        #expect(choreography.label == "1.5s")

        choreography.set(mode: .processing)
        #expect(choreography.label == Constants.processingLabel)

        choreography.set(mode: .result)
        #expect(choreography.label.isEmpty)

        choreography.set(mode: .error("boom"))
        #expect(choreography.label.isEmpty)
    }

    @Test func reduceMotionSuppressesShake() {
        var choreography = started(reduceMotion: true)
        choreography.set(mode: .error("boom"))

        for _ in 0..<10 {
            choreography.advance(dt: 0.01)
            #expect(choreography.shakeOffset == 0)
        }
    }
}
