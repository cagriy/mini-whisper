import Foundation

/// Sums the 16 kHz mono microphone and system-audio buffers of one tick (design §5.3).
public enum AudioMixer {
    /// Above this magnitude the sum is bent with `tanh` toward full scale.
    public static let limiterThreshold: Float = 0.9

    /// One output sample per microphone sample; missing system samples count as zeros.
    public static func mix(mic: [Float], system: [Float]) -> [Float] {
        mic.indices.map { index in
            limit(mic[index] + (index < system.count ? system[index] : 0))
        }
    }

    private static func limit(_ sample: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > limiterThreshold else { return sample }
        let headroom = 1 - limiterThreshold
        let bent = limiterThreshold + headroom * tanh((magnitude - limiterThreshold) / headroom)
        return Float(signOf: sample, magnitudeOf: bent)
    }
}
