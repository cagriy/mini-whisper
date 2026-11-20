import Testing

@testable import MWMeetingPipeline

@Suite struct VoiceAudioBufferTests {
    private static let ramp = (0..<16_000).map { Float($0) }

    @Test func returnsTheSamplesBetweenTwoTimes() {
        let buffer = VoiceAudioBuffer(seconds: 120)
        buffer.append(Self.ramp, at: 10)

        #expect(buffer.samples(from: 10.25, to: 10.5) == Array(Self.ramp[4_000..<8_000]))
        #expect(buffer.samples(from: 9, to: 12) == Self.ramp)
    }

    @Test func aRangeAcrossChunksJoinsTheirParts() {
        let buffer = VoiceAudioBuffer(seconds: 120)
        buffer.append(Array(Self.ramp[..<1_600]), at: 0)
        buffer.append(Array(Self.ramp[1_600..<3_200]), at: 0.1)

        #expect(buffer.samples(from: 0.05, to: 0.15) == Array(Self.ramp[800..<2_400]))
    }

    @Test func aGapYieldsOnlyTheAudioAroundIt() {
        let buffer = VoiceAudioBuffer(seconds: 120)
        buffer.append([Float](repeating: 1, count: 16_000), at: 0)
        buffer.append([Float](repeating: 2, count: 16_000), at: 5)

        let read = buffer.samples(from: 0.5, to: 5.5)
        #expect(read.count == 16_000)
        #expect(read == [Float](repeating: 1, count: 8_000) + [Float](repeating: 2, count: 8_000))
        #expect(buffer.samples(from: 1, to: 5).isEmpty)
    }

    @Test func evictsAudioOlderThanItsLength() {
        let buffer = VoiceAudioBuffer(seconds: 2)
        let audio = (0..<48_000).map { Float($0) }
        buffer.append(audio, at: 0)

        #expect(buffer.samples(from: 0, to: 1).isEmpty)
        #expect(buffer.samples(from: 1, to: 3) == Array(audio[16_000...]))

        // The next append moves the cut on, through the rest of the first chunk.
        buffer.append([Float](repeating: -1, count: 8_000), at: 3)
        #expect(buffer.samples(from: 0, to: 1.5).isEmpty)
        #expect(buffer.samples(from: 1.5, to: 3.5).count == 32_000)
        #expect(buffer.samples(from: 1.5, to: 1.5001).first == 24_000)
    }

    @Test func aRangeOutsideTheBufferIsEmpty() {
        let buffer = VoiceAudioBuffer(seconds: 120)
        #expect(buffer.samples(from: 0, to: 1).isEmpty)

        buffer.append(Self.ramp, at: 10)
        #expect(buffer.samples(from: 0, to: 10).isEmpty)
        #expect(buffer.samples(from: 11, to: 20).isEmpty)
        #expect(buffer.samples(from: 10.5, to: 10.25).isEmpty)
    }

    @Test func concurrentAppendAndReadNeverTear() async {
        let buffer = VoiceAudioBuffer(seconds: 2)
        let chunk = 1_600
        let chunks = 200

        let reads = await withTaskGroup(of: [Int].self) { group in
            group.addTask {
                for index in 0..<chunks {
                    let time = Double(index * chunk) / 16_000
                    buffer.append([Float](repeating: Float(index), count: chunk), at: time)
                }
                return []
            }
            group.addTask {
                (0..<chunks).map { _ in buffer.samples(from: 0, to: 30).count }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }

        #expect(reads.allSatisfy { $0 % chunk == 0 })
        let last = (180..<200).flatMap { [Float](repeating: Float($0), count: chunk) }
        #expect(buffer.samples(from: 0, to: 30) == last)
    }
}
