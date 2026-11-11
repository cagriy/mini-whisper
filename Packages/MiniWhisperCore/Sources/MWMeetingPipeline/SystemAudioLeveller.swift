import Foundation

/// Raises the call audio to speech level before it is mixed with the microphone.
///
/// Voice processing ducks other apps' audio and the process tap hears the call ducked; the
/// call app's own volume varies too. The gain follows a smoothed level of the chunks above
/// `speechFloorDBFS`, never cuts, and is ramped across each chunk so it never steps.
public struct SystemAudioLeveller: Sendable {
    public static let targetDBFS: Float = -26
    public static let maximumGainDB: Float = 24
    /// Quieter chunks are pauses or hiss: they hold the gain instead of pulling it up.
    public static let speechFloorDBFS: Float = -60
    /// Seconds for the level estimate to cover 63 % of a change.
    public static let timeConstant = 1.0
    public static let sampleRate = 16_000.0

    /// Starts at the target, so the gain starts at unity.
    private var levelDB = Double(targetDBFS)
    private var gainDB: Float = 0

    public init() {}

    public mutating func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let power = samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count)
        let chunkDB = 10 * log10(power)
        let from = gainDB
        if chunkDB > Double(Self.speechFloorDBFS) {
            let weight = 1 - exp(-Double(samples.count) / Self.sampleRate / Self.timeConstant)
            levelDB += weight * (chunkDB - levelDB)
            gainDB = min(max(Self.targetDBFS - Float(levelDB), 0), Self.maximumGainDB)
        }
        guard from != 0 || gainDB != 0 else { return samples }
        let start = Self.linear(from)
        let step = (Self.linear(gainDB) - start) / Float(samples.count)
        return samples.indices.map { samples[$0] * (start + step * Float($0 + 1)) }
    }

    private static func linear(_ decibels: Float) -> Float { pow(10, decibels / 20) }
}
