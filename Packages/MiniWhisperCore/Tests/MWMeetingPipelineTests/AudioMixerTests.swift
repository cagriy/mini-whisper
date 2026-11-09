import Testing

import MWMeetingPipeline

@Suite struct AudioMixerTests {
    private func expectClose(
        _ actual: [Float], _ expected: [Float], sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(actual.count == expected.count, sourceLocation: sourceLocation)
        for (a, e) in zip(actual, expected) {
            #expect(abs(a - e) < 1e-6, "\(a) vs \(e)", sourceLocation: sourceLocation)
        }
    }

    @Test func sumsBothSources() {
        expectClose(AudioMixer.mix(mic: [0.1, 0.2, -0.3], system: [0.2, -0.1, -0.1]), [0.3, 0.1, -0.4])
    }

    @Test func missingSourceContributesZeros() {
        expectClose(AudioMixer.mix(mic: [0.1, -0.2], system: []), [0.1, -0.2])
    }

    @Test func softLimiterKeepsTheOutputBelowOne() throws {
        let loud = try #require(AudioMixer.mix(mic: [0.8], system: [0.8]).first)
        #expect(loud > 0.9 && loud < 1.0)
        let negative = try #require(AudioMixer.mix(mic: [-0.8], system: [-0.8]).first)
        #expect(negative == -loud)

        // Up to the threshold the sum passes unchanged.
        expectClose(AudioMixer.mix(mic: [0.5], system: [0.4]), [0.9])
        #expect(AudioMixer.mix(mic: [1, -1], system: [1, -1]).allSatisfy { abs($0) <= 1 })
    }

    @Test func outputLengthFollowsTheMicBuffer() {
        expectClose(AudioMixer.mix(mic: [0.1, 0.1, 0.1], system: [0.1, 0.1, 0.1, 0.1, 0.1]), [0.2, 0.2, 0.2])
        expectClose(AudioMixer.mix(mic: [0.1, 0.1, 0.1], system: [0.1]), [0.2, 0.1, 0.1])
        #expect(AudioMixer.mix(mic: [], system: [0.5]).isEmpty)
    }
}
