/// `overlay.py:_tick`'s attack/decay one-pole, lifted out of
/// `ConstellationSimulation.updateLevel` so every overlay style moves on one envelope
/// (design §3 R7).
public struct LevelSmoother: Sendable {
    /// The smoothed 0–1 level the animation is scaled by.
    public private(set) var level = 0.0

    public init() {}

    /// Takes a raw per-buffer RMS and eases `level` towards its normalised value. The
    /// one-pole is per tick, not per second — the same frame-rate coupling the source
    /// has, kept for visual parity.
    public mutating func update(rms: Double) -> Double {
        let normalised = ConstellationSimulation.normalisedLevel(rms: rms)
        let coefficient = normalised > level ? Constants.smoothAttack : Constants.smoothDecay
        level += coefficient * (normalised - level)
        return level
    }

    public mutating func reset() {
        level = 0
    }
}
