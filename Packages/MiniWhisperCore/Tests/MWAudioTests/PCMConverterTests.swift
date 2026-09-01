import Foundation
import Testing
@testable import MWAudio
import MWTestSupport

/// Whole-buffer reference path: `recorder._resample` (linear interpolation over
/// `np.linspace` grids) followed by clip + int16, ported from
/// `../mini-whisper/tests/test_audio_convert.py::_batch_bytes`.
enum PCMReference {
    static func batch(_ samples: [Float], from origRate: Double, to targetRate: Double) -> [Int16] {
        resample(samples, from: origRate, to: targetRate).map { value in
            Int16(min(max(value, -1), 1) * 32767)
        }
    }

    private static func resample(
        _ samples: [Float], from origRate: Double, to targetRate: Double
    ) -> [Double] {
        guard origRate != targetRate else { return samples.map(Double.init) }
        let duration = Double(samples.count) / origRate
        let targetCount = Int(duration * targetRate)
        guard targetCount > 0 else { return [] }
        let origStep = duration / Double(samples.count)
        let targetStep = duration / Double(targetCount)
        return (0..<targetCount).map { j in
            interpolate(samples, at: Double(j) * targetStep / origStep)
        }
    }

    private static func interpolate(_ samples: [Float], at position: Double) -> Double {
        if position <= 0 { return Double(samples[0]) }
        if position >= Double(samples.count - 1) { return Double(samples[samples.count - 1]) }
        let index = Int(position)
        let fraction = position - Double(index)
        let lower = Double(samples[index])
        return lower + fraction * (Double(samples[index + 1]) - lower)
    }

    /// Decodes little-endian int16 PCM.
    static func int16LE(_ data: Data) -> [Int16] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - 1, by: 2).map {
            Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)
        }
    }
}

@Suite struct PCMConverterTests {

    private func chunked(
        _ samples: [Float], from origRate: Double, to targetRate: Double, chunk: Int
    ) -> Data {
        var converter = PCMConverter(from: origRate, to: targetRate)
        var out = Data()
        var position = 0
        while position < samples.count {
            let end = min(position + chunk, samples.count)
            out.append(converter.convert(Array(samples[position..<end])))
            position = end
        }
        return out
    }

    private func single(_ samples: [Float], from origRate: Double, to targetRate: Double) -> Data {
        var converter = PCMConverter(from: origRate, to: targetRate)
        return converter.convert(samples)
    }

    /// The Python suite allows ±1 between the chunked converter and the
    /// whole-signal `np.interp` reference; the two grids differ by a rounding.
    private func expectMatchesReference(
        _ data: Data, _ samples: [Float], from origRate: Double, to targetRate: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let actual = PCMReference.int16LE(data)
        let expected = PCMReference.batch(samples, from: origRate, to: targetRate)
        #expect(actual.count == expected.count, sourceLocation: sourceLocation)
        guard actual.count == expected.count else { return }
        let worst = zip(actual, expected).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 1, sourceLocation: sourceLocation)
    }

    @Test func singleCallMatchesBatch48kTo24k() {
        let samples = SignalFixtures.sine(count: 48000, sampleRate: 48000)
        expectMatchesReference(single(samples, from: 48000, to: 24000), samples, from: 48000, to: 24000)
    }

    @Test func chunkedMatchesBatch48kTo24k() {
        let samples = SignalFixtures.sine(count: 48000, sampleRate: 48000)
        let data = chunked(samples, from: 48000, to: 24000, chunk: 4096)
        expectMatchesReference(data, samples, from: 48000, to: 24000)
        #expect(data == single(samples, from: 48000, to: 24000))
    }

    @Test func chunkedMatchesBatch44_1kTo16k() {
        let samples = SignalFixtures.sine(count: 44100, sampleRate: 44100)
        let data = chunked(samples, from: 44100, to: 16000, chunk: 4096)
        expectMatchesReference(data, samples, from: 44100, to: 16000)
        #expect(data == single(samples, from: 44100, to: 16000))
    }

    /// The fractional resample position survives chunk boundaries: no dropped or
    /// duplicated samples for any split.
    @Test(arguments: [(48000.0, 16000.0, 1024), (44100.0, 24000.0, 333), (48000.0, 24000.0, 1)])
    func oddChunkSizesCarryState(origRate: Double, targetRate: Double, chunk: Int) {
        let samples = SignalFixtures.sine(count: Int(origRate), sampleRate: origRate)
        let data = chunked(samples, from: origRate, to: targetRate, chunk: chunk)
        #expect(data == single(samples, from: origRate, to: targetRate))
        expectMatchesReference(data, samples, from: origRate, to: targetRate)
    }

    @Test func outputIsInt16LE() {
        let data = single([Float](repeating: 0.5, count: 4800), from: 48000, to: 24000)
        let samples = PCMReference.int16LE(data)
        #expect(samples.count == 2400)
        #expect(samples.allSatisfy { $0 == 16383 })
        #expect([UInt8](data.prefix(2)) == [0xFF, 0x3F])
    }

    @Test func clipsToFullScale() {
        let ramp = SignalFixtures.ramp(count: 4800, from: -1.5, to: 1.5)
        let samples = PCMReference.int16LE(single(ramp, from: 48000, to: 24000))
        #expect(samples.first == -32767)
        #expect(samples.last == 32767)
        #expect(samples.allSatisfy { $0 >= -32767 && $0 <= 32767 })
    }

    @Test func sameRatePassthrough() {
        let samples = SignalFixtures.sine(count: 16000, sampleRate: 16000)
        let data = chunked(samples, from: 16000, to: 16000, chunk: 1000)
        expectMatchesReference(data, samples, from: 16000, to: 16000)
        #expect(data == single(samples, from: 16000, to: 16000))
    }

    @Test func emptyChunkIsNoop() {
        var converter = PCMConverter(from: 48000, to: 24000)
        #expect(converter.convert([]).isEmpty)
        let samples = SignalFixtures.sine(count: 4800, sampleRate: 48000)
        #expect(converter.convert(samples).count == 4800)
    }

    @Test func nonFiniteSamplesBecomeSilence() {
        let data = single([.nan, .nan, .nan, .nan], from: 48000, to: 48000)
        #expect(PCMReference.int16LE(data) == [0, 0, 0, 0])
    }
}
