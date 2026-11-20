import Foundation
import MWMeetings
import MWTestSupport
import Testing

import MWVoices

@Suite struct SampleSetTests {
    private static let start = Date(timeIntervalSince1970: 1_793_491_200)  // 2026-11-01T00:00:00Z

    private func sample(_ vector: VoiceVector, day: Int, meeting: UUID = UUID()) -> LocalSample {
        LocalSample(meeting: meeting, at: Self.start.addingTimeInterval(Double(day) * 86_400), seconds: 30, vector: vector)
    }

    /// Cosine with `.unit(0)` exactly 17/20 = 0.85.
    private let atPointEightFive = VoiceVector.padded([17, 10, 3, 1, 1])

    @Test func aSampleAtPointEightFiveOrCloserReplacesTheClosest() {
        let first = sample(.unit(0), day: 1)
        let orthogonal = sample(.unit(5), day: 2)
        let new = sample(atPointEightFive, day: 3)
        #expect(SampleSet.adding(new, to: [first, orthogonal]) == [orthogonal, new])

        let closer = sample(atPointEightFive, day: 2)
        let other = sample(.unit(9), day: 4)
        #expect(SampleSet.adding(new, to: [first, closer, other]) == [first, other, new])
    }

    @Test func aDistantSampleIsAdded() {
        let first = sample(.unit(0), day: 1)
        let justBelow = sample(.padded([21, 12, 6, 2]), day: 2)  // cosine 21/25 = 0.84

        #expect(SampleSet.adding(justBelow, to: [first]) == [first, justBelow])
        #expect(SampleSet.adding(first, to: []) == [first])
    }

    @Test func theNinthDistantSampleDropsTheOldest() {
        let days = [5, 6, 7, 1, 8, 9, 10, 11]  // the oldest is fourth
        let eight = days.enumerated().map { sample(.unit($0.offset), day: $0.element) }
        let filled = eight.reduce([LocalSample]()) { SampleSet.adding($1, to: $0) }
        #expect(filled == eight)
        #expect(SampleSet.capacity == 8)

        let ninth = sample(.unit(8), day: 12)
        let result = SampleSet.adding(ninth, to: filled)

        #expect(result.count == 8)
        #expect(result == eight.filter { $0 != eight[3] } + [ninth])

        let overfull = eight + [sample(.unit(10), day: 0), sample(.unit(11), day: 2)]
        #expect(SampleSet.adding(ninth, to: overfull) == eight.filter { $0 != eight[3] } + [ninth])
    }

    @Test func aSecondSampleFromTheSameMeetingReplacesThatMeetingsSample() {
        let meeting = UUID()
        let earlier = sample(.unit(0), day: 1, meeting: meeting)
        let other = sample(.unit(1), day: 2)
        let recomputed = sample(.unit(2), day: 3, meeting: meeting)

        #expect(SampleSet.adding(recomputed, to: [earlier, other]) == [other, recomputed])
    }
}
