import Foundation

/// SplitMix64 with a Box–Muller normal on top: the overlay's only source of randomness, so
/// a seed makes the whole simulation reproducible (design §5.12).
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    private var spare: Double?

    public init(seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `[0, 1)`, from the top 53 bits so every value is exactly representable.
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    public mutating func uniform(_ lower: Double, _ upper: Double) -> Double {
        lower + unit() * (upper - lower)
    }

    /// Standard normal; the second Box–Muller value is kept for the next call.
    public mutating func gaussian() -> Double {
        if let spare {
            self.spare = nil
            return spare
        }
        var u = unit()
        if u <= 0 { u = Double.leastNormalMagnitude }
        let radius = (-2 * Foundation.log(u)).squareRoot()
        let theta = 2 * Double.pi * unit()
        spare = radius * Foundation.sin(theta)
        return radius * Foundation.cos(theta)
    }
}
