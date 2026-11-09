import Foundation

/// Stateful chunked float32 resampler with an int16 LE output (N2) and a float
/// output (the meeting pipeline's 16 kHz path).
///
/// Port of `streaming/audio_convert.py`: the fractional resample position
/// (`nextOut`, `totalIn`) and the input `tail` still needed for interpolation
/// carry across chunks, so any split of a signal produces byte-identical output
/// to converting it in one call.
public struct PCMConverter: Sendable {
    /// Input samples per output sample.
    private let ratio: Double
    /// Next global output-sample index to emit.
    private var nextOut = 0
    /// Global input samples consumed so far.
    private var totalIn = 0
    /// Input tail still needed to interpolate the next outputs.
    private var tail: [Float] = []

    public init(from origRate: Double, to targetRate: Double) {
        ratio = origRate / targetRate
    }

    public mutating func convert(_ samples: [Float]) -> Data {
        let values = step(samples)
        var out = Data()
        out.reserveCapacity(values.count * 2)
        for value in values {
            let scaled = min(max(value, -1), 1) * 32767
            withUnsafeBytes(of: (scaled.isFinite ? Int16(scaled) : 0).littleEndian) {
                out.append(contentsOf: $0)
            }
        }
        return out
    }

    /// The same resampling as `convert(_:)`, unclipped, as floats.
    public mutating func resample(_ samples: [Float]) -> [Float] {
        step(samples).map { Float($0) }
    }

    /// Consumes `samples` and returns the outputs they fully determine.
    private mutating func step(_ samples: [Float]) -> LazyMapCollection<Range<Int>, Double> {
        let ratio = ratio
        guard !samples.isEmpty else { return (0..<0).lazy.map { _ in 0 } }

        // Global index of buffer[0].
        let base = totalIn - tail.count
        let buffer = tail.isEmpty ? samples : tail + samples
        totalIn += samples.count

        // Output j sits at input position j * ratio; emit while fully determined
        // by the input seen so far.
        let lastOut = Int((Double(totalIn - 1) / ratio).rounded(.down))
        let outputs = nextOut..<max(nextOut, lastOut + 1)
        nextOut = outputs.upperBound

        let keepFrom = min(max(Int((Double(nextOut) * ratio).rounded(.down)) - base, 0), buffer.count)
        tail = Array(buffer[keepFrom...])
        return outputs.lazy.map { j in Self.interpolate(buffer, at: Double(j) * ratio - Double(base)) }
    }

    /// `np.interp` over the buffer's own indices, clamped at both ends.
    private static func interpolate(_ buffer: [Float], at position: Double) -> Double {
        if position <= 0 { return Double(buffer[0]) }
        if position >= Double(buffer.count - 1) { return Double(buffer[buffer.count - 1]) }
        let index = Int(position)
        let lower = Double(buffer[index])
        return lower + (position - Double(index)) * (Double(buffer[index + 1]) - lower)
    }
}
