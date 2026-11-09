import Testing

import MWMeetingPipeline

@Suite struct SystemAudioRingTests {
    @Test func holdsAtMostTwoSeconds() {
        #expect(SystemAudioRing.capacity == 32_000)
        let ring = SystemAudioRing()
        let samples = (0..<40_000).map { Float($0) }

        ring.push(Array(samples[..<25_000]))
        ring.push(Array(samples[25_000...]))

        #expect(ring.count == 32_000)
        // The oldest samples are dropped.
        #expect(ring.take(32_000) == Array(samples[8_000...]))
        #expect(ring.count == 0)
    }

    @Test func takeReturnsTheRequestedCountPaddingWithZeros() {
        let ring = SystemAudioRing()
        ring.push([1, 2, 3, 4, 5])

        #expect(ring.take(2) == [1, 2])
        #expect(ring.take(5) == [3, 4, 5, 0, 0])
        #expect(ring.take(2) == [0, 0])
        #expect(ring.take(0).isEmpty)
    }

    @Test func peakSinceReportsTheLoudestSample() {
        let ring = SystemAudioRing()
        #expect(ring.peakSinceLastCall() == 0)

        ring.push([0.1, -0.5, 0.2])
        ring.push([0.3])
        _ = ring.take(4)

        // Taking samples does not hide them from the peak.
        #expect(ring.peakSinceLastCall() == 0.5)
        #expect(ring.peakSinceLastCall() == 0)
        ring.push([0.05])
        #expect(ring.peakSinceLastCall() == 0.05)
    }
}
