import MWMeetings
import Testing

import MWVoices

private func close(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}

@Suite struct VoiceWindowTests {
    private func word(_ start: Double, _ end: Double) -> Word {
        Word(text: "word", start: start, end: end)
    }

    /// `seconds` of 16 kHz audio counting up from `first`, so a cut can be traced back.
    private func ramp(_ seconds: Double, from first: Int = 0) -> [Float] {
        (first..<first + Int((seconds * 16_000).rounded())).map(Float.init)
    }

    private func bounds(_ spans: [Range<Double>]) -> [[Double]] {
        spans.map { [$0.lowerBound, $0.upperBound] }
    }

    private func matches(_ spans: [Range<Double>], _ expected: [[Double]]) -> Bool {
        let actual = bounds(spans)
        return actual.count == expected.count
            && zip(actual, expected).allSatisfy { close($0[0], $1[0]) && close($0[1], $1[1]) }
    }

    @Test func wordsAtMostThreeTenthsApartMerge() {
        // 1.3 − 1.0 is 0.30000000000000004 in binary, a hair over the gap.
        let merged = VoiceWindow.spans(of: [word(0.5, 1.0), word(1.3, 2.0)])
        #expect(matches(merged, [[0.45, 2.05]]))

        let apart = VoiceWindow.spans(of: [word(0.5, 1.0), word(1.31, 2.0)])
        #expect(matches(apart, [[0.45, 1.05], [1.26, 2.05]]))

        let chained = VoiceWindow.spans(of: [word(0.5, 1.0), word(1.3, 2.0), word(2.31, 3.0), word(3.2, 3.5)])
        #expect(matches(chained, [[0.45, 2.05], [2.26, 3.55]]))

        let overlapping = VoiceWindow.spans(of: [word(0.5, 1.2), word(1.0, 1.1)])
        #expect(matches(overlapping, [[0.45, 1.25]]))
    }

    @Test func spansArePaddedFiveHundredthsEachSide() {
        #expect(matches(VoiceWindow.spans(of: [word(1.0, 1.4)]), [[0.95, 1.45]]))
        #expect(matches(VoiceWindow.spans(of: [word(1.0, 1.4), word(4.0, 4.2)]), [[0.95, 1.45], [3.95, 4.25]]))
        #expect(VoiceWindow.spans(of: []).isEmpty)
    }

    @Test func speechSecondsIsTheMergedPaddedLength() {
        // 0.95–3.05 (2.1 s) and 4.95–5.55 (0.6 s).
        let words = [word(1.0, 2.0), word(2.2, 3.0), word(5.0, 5.5)]
        #expect(close(VoiceWindow.speechSeconds(of: words), 2.7))
        #expect(VoiceWindow.speechSeconds(of: []) == 0)
    }

    @Test func longSpeechSplitsIntoTenSecondWindows() {
        let audio = ramp(23)
        let windows = VoiceWindow.windows(from: audio)

        #expect(windows.map(\.seconds) == [10, 10, 3])
        #expect(windows.allSatisfy { $0.samples.count == 160_000 })
        #expect(windows.first?.samples == Array(audio[0..<160_000]))
        #expect(windows.dropFirst().first?.samples == Array(audio[160_000..<320_000]))
        #expect(windows.last?.samples.first == 320_000)
    }

    @Test func aTailUnderOneAndAHalfSecondsIsDropped() {
        #expect(VoiceWindow.windows(from: ramp(21)).map(\.seconds) == [10, 10])
        #expect(VoiceWindow.windows(from: ramp(21.5)).map(\.seconds) == [10, 10, 1.5])
    }

    @Test func underOneAndAHalfSecondsYieldsNoWindow() {
        #expect(VoiceWindow.windows(from: []).isEmpty)
        #expect(VoiceWindow.windows(from: Array(ramp(1.5).dropLast())).isEmpty)
        #expect(VoiceWindow.windows(from: ramp(1.5)).map(\.seconds) == [1.5])

        // 0.95–2.35: 1.4 s of padded word audio.
        let short = VoiceWindow.spans(of: [word(1.0, 2.3)])
        #expect(VoiceWindow.windows(spans: short) { ramp($1 - $0) }.isEmpty)
    }

    @Test func eachWindowIsLoopedTo160000Samples() throws {
        let audio = ramp(2)
        let window = try #require(VoiceWindow.windows(from: audio).first)

        #expect(window.samples.count == 160_000)
        #expect(window.seconds == 2)
        #expect(Array(window.samples[0..<32_000]) == audio)
        #expect(window.samples[32_000] == window.samples[0])
        #expect(window.samples[32_001] == audio[1])
        #expect(window.samples[159_999] == audio[159_999 % 32_000])
    }

    @Test func theSpansAreReadInOrderAndJoined() throws {
        // 0.95–2.05 and 3.95–5.05: 1.1 s each.
        let spans = VoiceWindow.spans(of: [word(1.0, 2.0), word(4.0, 5.0)])
        var reads: [[Double]] = []
        let windows = VoiceWindow.windows(spans: spans) { start, end in
            reads.append([start, end])
            return ramp(end - start, from: reads.count * 100_000)
        }

        #expect(reads == bounds(spans))
        let window = try #require(windows.first)
        #expect(windows.count == 1)
        #expect(close(window.seconds, 2.2))
        #expect(Array(window.samples[0..<35_200]) == ramp(1.1, from: 100_000) + ramp(1.1, from: 200_000))
    }

    @Test func aPartialBufferUsesWhatIsThere() {
        // 0.95–13.05: 12.1 s of speech, of which the buffer holds the later half.
        let spans = VoiceWindow.spans(of: [word(1.0, 13.0)])
        let whole = VoiceWindow.windows(spans: spans) { ramp($1 - $0) }
        #expect(whole.count == 2)
        #expect(close(whole.last?.seconds ?? 0, 2.1))

        let halved = VoiceWindow.windows(spans: spans) { start, end in ramp((end - start) / 2) }
        #expect(halved.count == 1)
        #expect(close(halved.first?.seconds ?? 0, 6.05))
        #expect(halved.first?.samples.count == 160_000)

        let gone = VoiceWindow.windows(spans: spans) { _, _ in [] }
        #expect(gone.isEmpty)
    }
}
