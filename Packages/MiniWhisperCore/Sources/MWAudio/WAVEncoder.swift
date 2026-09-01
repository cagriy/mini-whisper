import Foundation

/// 16 kHz mono 16-bit WAV, matching `recorder.stop()` (N2).
public enum WAVEncoder {
    private static let targetSampleRate: Double = 16000
    private static let channels: UInt16 = 1
    private static let bitsPerSample: UInt16 = 16

    public static func encode(samples: [Float], sampleRate: Double) -> Data {
        var converter = PCMConverter(from: sampleRate, to: targetSampleRate)
        let pcm = converter.convert(samples)

        let blockAlign = channels * bitsPerSample / 8
        let byteRate = UInt32(targetSampleRate) * UInt32(blockAlign)

        var wav = Data(capacity: 44 + pcm.count)
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.append(littleEndian: UInt32(36 + pcm.count))
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        wav.append(littleEndian: UInt32(16))
        wav.append(littleEndian: UInt16(1))  // PCM
        wav.append(littleEndian: channels)
        wav.append(littleEndian: UInt32(targetSampleRate))
        wav.append(littleEndian: byteRate)
        wav.append(littleEndian: blockAlign)
        wav.append(littleEndian: bitsPerSample)
        wav.append(contentsOf: Array("data".utf8))
        wav.append(littleEndian: UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }
}

extension Data {
    fileprivate mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
