import Foundation
import MWTestSupport
import Testing

import MWMeetingPipeline

@Suite struct SystemAudioLevellerTests {
    /// About what one microphone tick takes from the ring at 44.1 kHz.
    private static let chunk = 341

    private static func dbfs<C: Collection<Float>>(_ samples: C) -> Float {
        let power = samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count)
        return Float(10 * log10(power))
    }

    private static func tone(dbfs: Float, seconds: Double) -> [Float] {
        let amplitude = Float(pow(10, Double(dbfs) / 20) * 2.0.squareRoot())
        return SignalFixtures.sine(count: Int(seconds * 16_000), sampleRate: 16_000, amplitude: amplitude, noise: 0)
    }

    private static func chunks(_ input: [Float]) -> [[Float]] {
        stride(from: 0, to: input.count, by: chunk).map { Array(input[$0..<min($0 + chunk, input.count)]) }
    }

    private static func run(_ input: [Float], through leveller: inout SystemAudioLeveller) -> [Float] {
        chunks(input).flatMap { leveller.process($0) }
    }

    @Test func raisesADuckedCallToTheTargetLevel() {
        var leveller = SystemAudioLeveller()
        let out = Self.run(Self.tone(dbfs: -46, seconds: 6), through: &leveller)
        #expect(abs(Self.dbfs(out.suffix(16_000)) - SystemAudioLeveller.targetDBFS) < 1)
    }

    @Test func gainStartsAtUnityAndRisesWithoutSteps() {
        var leveller = SystemAudioLeveller()
        let gains = Self.chunks(Self.tone(dbfs: -46, seconds: 2)).map { chunk in
            Self.dbfs(leveller.process(chunk)) - Self.dbfs(chunk)
        }
        #expect(abs(gains[0]) < 1)
        for (before, after) in zip(gains, gains.dropFirst()) {
            #expect(after >= before - 0.01 && after - before < 1, "\(before) → \(after) dB")
        }
        #expect(gains.last! > 10)
    }

    @Test func speechAtOrAboveTheTargetPassesUnchanged() {
        var leveller = SystemAudioLeveller()
        let call = Self.tone(dbfs: -20, seconds: 3)
        #expect(Self.run(call, through: &leveller) == call)
    }

    @Test func gainIsCapped() {
        var leveller = SystemAudioLeveller()
        let out = Self.run(Self.tone(dbfs: -55, seconds: 10), through: &leveller)
        #expect(abs(Self.dbfs(out.suffix(16_000)) - (-55 + SystemAudioLeveller.maximumGainDB)) < 1)
    }

    @Test func faintNoiseIsNotPulledUp() {
        var leveller = SystemAudioLeveller()
        let hiss = Self.tone(dbfs: -70, seconds: 5)
        #expect(Self.run(hiss, through: &leveller) == hiss)
    }

    @Test func aPauseHoldsTheGain() {
        var leveller = SystemAudioLeveller()
        _ = Self.run(Self.tone(dbfs: -46, seconds: 6), through: &leveller)
        let pause = [Float](repeating: 0, count: 3 * 16_000)
        #expect(Self.run(pause, through: &leveller) == pause)
        let resumed = Self.run(Self.tone(dbfs: -46, seconds: 0.5), through: &leveller)
        #expect(abs(Self.dbfs(resumed) - SystemAudioLeveller.targetDBFS) < 1.5)
    }
}
