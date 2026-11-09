import Foundation

/// A stretch of microphone speech, in meeting seconds.
public struct SpeechSpan: Sendable, Equatable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// Microphone voice-activity gate over 16 kHz mono float (design §5.3).
///
/// A 20 ms frame is loud when its RMS exceeds both `floorRatio` × the noise floor (the
/// `floorPercentile` of the last `floorWindowSeconds` of frames) and `minimumDBFS`.
/// `onsetFrames` loud frames in a row open a span, back-dated to the first of them;
/// `releaseSeconds` of quiet frames close it at the end of its last loud frame.
public struct SpeechGate: Sendable {
    public static let sampleRate = 16_000.0
    public static let frameSamples = 320
    public static let onsetFrames = 3
    public static let releaseSeconds = 0.3
    public static let floorRatio: Float = 4
    public static let minimumDBFS: Float = -45
    public static let floorPercentile = 0.05
    public static let floorWindowSeconds = 10.0
    /// Closed spans older than this, measured from the latest frame, are dropped.
    public static let retentionSeconds = 600.0

    private static let releaseFrames = Int((releaseSeconds * sampleRate / Double(frameSamples)).rounded())
    private static let minimumRMS = pow(10, minimumDBFS / 20)

    /// What the attributor and the partial tagging read.
    public struct View: Sendable, Equatable {
        /// In time order, not overlapping; the open span last, up to its latest loud frame.
        public var spans: [SpeechSpan]
        public var isSpeakingNow: Bool

        public init(spans: [SpeechSpan] = [], isSpeakingNow: Bool = false) {
            self.spans = spans
            self.isSpeakingNow = isSpeakingNow
        }

        /// The fraction of `start...end` inside speech; a zero-length word counts 1 inside a span.
        public func overlap(start: Double, end: Double) -> Double {
            // First span that does not end before `start`.
            var low = 0
            var high = spans.count
            while low < high {
                let mid = (low + high) / 2
                if spans[mid].end < start { low = mid + 1 } else { high = mid }
            }
            guard end > start else {
                return low < spans.count && spans[low].start <= start ? 1 : 0
            }
            var covered = 0.0
            var index = low
            while index < spans.count, spans[index].start < end {
                covered += max(0, min(end, spans[index].end) - max(start, spans[index].start))
                index += 1
            }
            return min(covered / (end - start), 1)
        }
    }

    /// Samples short of a whole frame, carried into the next push.
    private var pending: [Float] = []
    private var floor = RunningPercentile(
        window: Int(floorWindowSeconds * sampleRate) / frameSamples, percentile: floorPercentile
    )
    private var closed: [SpeechSpan] = []
    private var open: SpeechSpan?
    private var loudRun = 0
    private var onsetStart = 0.0
    private var quietRun = 0

    public init() {}

    public var isSpeakingNow: Bool { open != nil }

    public var view: View {
        View(spans: open.map { closed + [$0] } ?? closed, isSpeakingNow: isSpeakingNow)
    }

    /// Feeds samples whose first one sits at meeting second `time`.
    public mutating func push(_ samples: [Float], at time: Double) {
        let buffer = pending + samples
        let frame = Self.frameSamples
        // Meeting time of a buffer offset.
        let timeAt = { [count = pending.count] (offset: Int) in time + Double(offset - count) / Self.sampleRate }
        var offset = 0
        while offset + frame <= buffer.count {
            process(buffer[offset..<(offset + frame)], start: timeAt(offset), end: timeAt(offset + frame))
            offset += frame
        }
        pending = Array(buffer[offset...])

        let cutoff = timeAt(offset) - Self.retentionSeconds
        if let kept = closed.firstIndex(where: { $0.end >= cutoff }) {
            closed.removeFirst(kept)
        } else {
            closed.removeAll()
        }
    }

    private mutating func process(_ frame: ArraySlice<Float>, start: Double, end: Double) {
        let energy = (frame.reduce(Float(0)) { $0 + $1 * $1 } / Float(frame.count)).squareRoot()
        let rms = energy.isFinite ? energy : 0
        let loud = rms > Self.minimumRMS && rms > floor.value * Self.floorRatio
        floor.add(rms)

        if var span = open {
            if loud {
                span.end = end
                open = span
                quietRun = 0
            } else {
                quietRun += 1
                if quietRun >= Self.releaseFrames {
                    closed.append(span)
                    open = nil
                    quietRun = 0
                }
            }
        } else if loud {
            loudRun += 1
            if loudRun == 1 { onsetStart = start }
            if loudRun == Self.onsetFrames {
                open = SpeechSpan(start: onsetStart, end: end)
                loudRun = 0
            }
        } else {
            loudRun = 0
        }
    }
}

/// A percentile over the last `window` values: a FIFO plus a sorted copy.
///
/// The window starts as zeros, the silence before the meeting, so the floor stays 0 and
/// only the absolute threshold applies until real frames fill most of it.
private struct RunningPercentile: Sendable {
    private let percentile: Double
    private var fifo: [Float]
    private var head = 0
    private var sorted: [Float]

    init(window: Int, percentile: Double) {
        self.percentile = percentile
        fifo = [Float](repeating: 0, count: window)
        sorted = fifo
    }

    var value: Float { sorted[Int(Double(sorted.count - 1) * percentile)] }

    mutating func add(_ value: Float) {
        sorted.remove(at: insertionIndex(of: fifo[head]))
        fifo[head] = value
        head = (head + 1) % fifo.count
        sorted.insert(value, at: insertionIndex(of: value))
    }

    /// The first index whose value is not below `value`.
    private func insertionIndex(of value: Float) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
