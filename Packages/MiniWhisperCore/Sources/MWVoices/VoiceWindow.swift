import MWMeetings

/// R6: a turn's words → the speech they cover → model windows of 16 kHz audio.
public enum VoiceWindow {
    public static let sampleRate = 16_000.0
    public static let maximumSeconds = 10.0
    /// The model's input: `maximumSeconds` at `sampleRate`.
    public static let windowSamples = Int(maximumSeconds * sampleRate)
    public static let minimumSeconds = 1.5
    /// Words this close or closer are one span.
    public static let mergeGap = 0.3
    /// Added before and after each span.
    public static let padding = 0.05

    /// Word times are decimal seconds, and their differences land a hair either side of the gap
    /// (1.3 − 1.0 = 0.30000000000000004), so a met boundary counts.
    private static let tolerance = 1e-9
    private static let minimumSamples = Int((minimumSeconds * sampleRate).rounded())

    public struct Window: Sendable, Equatable {
        /// Exactly `windowSamples`, the speech looped from its start when shorter.
        public var samples: [Float]
        /// The speech before looping.
        public var seconds: Double
    }

    /// The meeting-time spans the words cover, merged and padded, in word order.
    public static func spans(of words: [Word]) -> [Range<Double>] {
        var merged: [(start: Double, end: Double)] = []
        for word in words {
            let end = max(word.start, word.end)
            if let last = merged.last, word.start - last.end <= mergeGap + tolerance {
                merged[merged.count - 1] = (min(last.start, word.start), max(last.end, end))
            } else {
                merged.append((word.start, end))
            }
        }
        return merged.map { ($0.start - padding)..<($0.end + padding) }
    }

    public static func speechSeconds(of words: [Word]) -> Double {
        spans(of: words).reduce(0) { $0 + $1.upperBound - $1.lowerBound }
    }

    /// Consecutive windows of at most `maximumSeconds`; one under `minimumSeconds` is dropped.
    public static func windows(from samples: [Float]) -> [Window] {
        stride(from: 0, to: samples.count, by: windowSamples).compactMap { first in
            let speech = samples[first..<min(first + windowSamples, samples.count)]
            guard speech.count >= minimumSamples else { return nil }
            var looped: [Float] = []
            looped.reserveCapacity(windowSamples)
            while looped.count < windowSamples {
                looped += speech.prefix(windowSamples - looped.count)
            }
            return Window(samples: looped, seconds: Double(speech.count) / sampleRate)
        }
    }

    /// The windows of the audio `read` returns for each span, joined in order. A read may return
    /// less than its span (audio older than the buffer, or a gap); what it returns is used.
    public static func windows(spans: [Range<Double>], read: (_ start: Double, _ end: Double) -> [Float]) -> [Window] {
        windows(from: spans.flatMap { read($0.lowerBound, $0.upperBound) })
    }
}
