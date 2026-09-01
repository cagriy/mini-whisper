import Foundation

/// Deterministic float32 signals for the audio tests, mirroring the generators
/// in `../mini-whisper/tests/test_audio_convert.py`.
public enum SignalFixtures {
    /// A 440 Hz sine with a little additive noise, seeded so failures reproduce.
    public static func sine(
        count: Int,
        sampleRate: Double,
        frequency: Double = 440,
        amplitude: Float = 0.6,
        noise: Float = 0.05,
        seed: UInt64 = 42
    ) -> [Float] {
        var state = seed
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            let tone = amplitude * Float(sin(2 * .pi * frequency * t))
            return tone + noise * nextGaussian(&state)
        }
    }

    /// A linear sweep, used to exercise clipping at both rails.
    public static func ramp(count: Int, from start: Float, to end: Float) -> [Float] {
        guard count > 1 else { return count == 1 ? [start] : [] }
        let step = (end - start) / Float(count - 1)
        return (0..<count).map { start + Float($0) * step }
    }

    /// Box–Muller over a SplitMix64 stream.
    private static func nextGaussian(_ state: inout UInt64) -> Float {
        let u1 = max(nextUnitInterval(&state), .leastNormalMagnitude)
        let u2 = nextUnitInterval(&state)
        return Float((-2 * log(u1)).squareRoot() * cos(2 * .pi * u2))
    }

    private static func nextUnitInterval(_ state: inout UInt64) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) * 0x1p-53
    }
}
