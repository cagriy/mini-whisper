import Foundation
import MWTestSupport
import Testing

import MWMeetingPipeline

@Suite struct SpeechGateTests {
    private static let rate = 16_000.0

    /// `count` 20 ms frames of a 440 Hz tone whose RMS sits at `dBFS`.
    private func tone(_ count: Int, dBFS: Float) -> [Float] {
        let rms = pow(10, dBFS / 20)
        return SignalFixtures.sine(
            count: count * 320, sampleRate: Self.rate, amplitude: rms * Float(2).squareRoot(), noise: 0
        )
    }

    private func loud(_ count: Int) -> [Float] { tone(count, dBFS: -20) }

    private func silence(_ count: Int) -> [Float] { [Float](repeating: 0, count: count * 320) }

    private func expectSpans(
        _ gate: SpeechGate, _ expected: [(Double, Double)],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let spans = gate.view.spans
        #expect(spans.count == expected.count, sourceLocation: sourceLocation)
        for (span, (start, end)) in zip(spans, expected) {
            #expect(abs(span.start - start) < 1e-9, "start \(span.start)", sourceLocation: sourceLocation)
            #expect(abs(span.end - end) < 1e-9, "end \(span.end)", sourceLocation: sourceLocation)
        }
    }

    @Test func onsetNeedsThreeConsecutiveLoudFrames() {
        var gate = SpeechGate()
        gate.push(silence(10) + loud(2) + silence(1) + loud(2), at: 0)
        #expect(!gate.isSpeakingNow)
        #expect(gate.view.spans.isEmpty)

        gate.push(loud(1), at: 0.3)

        #expect(gate.isSpeakingNow)
        // Back-dated to the first of the three frames.
        expectSpans(gate, [(0.26, 0.32)])
    }

    @Test func releaseAfter300MillisecondsBelowThreshold() {
        var gate = SpeechGate()
        gate.push(loud(10), at: 0)
        gate.push(silence(14), at: 0.2)
        #expect(gate.isSpeakingNow)

        gate.push(silence(1), at: 0.48)

        #expect(!gate.isSpeakingNow)
        expectSpans(gate, [(0, 0.2)])
    }

    @Test func aDipShorterThanTheReleaseKeepsOneSpan() {
        var gate = SpeechGate()
        gate.push(loud(10) + silence(10) + loud(5) + silence(15), at: 0)
        expectSpans(gate, [(0, 0.5)])
    }

    @Test func framesBelowMinus45dBFSNeverOpen() {
        var gate = SpeechGate()
        gate.push(silence(10) + tone(100, dBFS: -50), at: 0)
        #expect(!gate.isSpeakingNow)
        #expect(gate.view.spans.isEmpty)

        gate.push(tone(3, dBFS: -40), at: 2.2)
        #expect(gate.isSpeakingNow)
    }

    @Test func noiseFloorAdaptsOverTenSeconds() throws {
        var gate = SpeechGate()
        let hiss = SignalFixtures.sine(count: 500 * 320, sampleRate: Self.rate, amplitude: 0, noise: 0.0003)
        gate.push(hiss, at: 0)
        gate.push(loud(250), at: 10)
        #expect(gate.isSpeakingNow)

        // The same level for ten seconds becomes the floor and stops counting.
        gate.push(loud(300), at: 15)

        #expect(!gate.isSpeakingNow)
        #expect(gate.view.spans.count == 1)
        let span = try #require(gate.view.spans.first)
        #expect(span.end > 19 && span.end < 20)
    }

    @Test func spansAreStampedInMeetingTime() {
        let samples = silence(25) + loud(50) + silence(25)
        var whole = SpeechGate()
        whole.push(samples, at: 100)
        expectSpans(whole, [(100.5, 101.5)])

        // Buffers that do not align with 20 ms frames give the same spans.
        var chunked = SpeechGate()
        for start in stride(from: 0, to: samples.count, by: 341) {
            let chunk = Array(samples[start..<min(start + 341, samples.count)])
            chunked.push(chunk, at: 100 + Double(start) / Self.rate)
        }
        expectSpans(chunked, [(100.5, 101.5)])
    }

    @Test func ringKeepsTheLastTenMinutes() {
        var gate = SpeechGate()
        for start in [0.0, 100, 650] {
            gate.push(loud(25) + silence(25), at: start)
        }
        // At 651 s the span ending at 0.5 s is older than ten minutes.
        expectSpans(gate, [(100, 100.5), (650, 650.5)])
    }

    @Test func overlapFractionOfAWord() {
        var gate = SpeechGate()
        gate.push(silence(50) + loud(50) + silence(25) + loud(25) + silence(25), at: 0)
        expectSpans(gate, [(1, 2), (2.5, 3)])
        let view = gate.view

        #expect(abs(view.overlap(start: 1.5, end: 2.5) - 0.5) < 1e-9)
        #expect(abs(view.overlap(start: 1.75, end: 2.75) - 0.5) < 1e-9)
        #expect(view.overlap(start: 0.2, end: 0.8) == 0)
        #expect(view.overlap(start: 1.2, end: 1.8) == 1)
        #expect(view.overlap(start: 1.4, end: 1.4) == 1)
        #expect(view.overlap(start: 2.2, end: 2.2) == 0)
    }

    @Test func isSpeakingNowFollowsTheOpenSpan() {
        var gate = SpeechGate()
        gate.push(silence(5) + loud(3), at: 0)
        #expect(gate.view.isSpeakingNow)
        expectSpans(gate, [(0.1, 0.16)])

        gate.push(loud(2), at: 0.16)
        expectSpans(gate, [(0.1, 0.2)])
        #expect(abs(gate.view.overlap(start: 0.1, end: 0.2) - 1) < 1e-9)

        gate.push(silence(15), at: 0.2)
        #expect(!gate.view.isSpeakingNow)
        expectSpans(gate, [(0.1, 0.2)])
    }
}
