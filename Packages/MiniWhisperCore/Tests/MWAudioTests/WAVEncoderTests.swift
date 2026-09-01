import Foundation
import Testing
@testable import MWAudio
import MWTestSupport

@Suite struct WAVEncoderTests {

    private func string(_ data: Data, _ range: Range<Int>) -> String {
        String(decoding: data[range], as: UTF8.self)
    }

    private func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        [UInt8](data[offset..<(offset + 4)]).reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    private func uint16(_ data: Data, _ offset: Int) -> UInt16 {
        [UInt8](data[offset..<(offset + 2)]).reversed().reduce(0) { $0 << 8 | UInt16($1) }
    }

    @Test func headerFieldsFor16kMono16bit() {
        let wav = WAVEncoder.encode(samples: SignalFixtures.sine(count: 48000, sampleRate: 48000), sampleRate: 48000)
        let dataSize = UInt32(wav.count - 44)

        #expect(string(wav, 0..<4) == "RIFF")
        #expect(uint32(wav, 4) == 36 + dataSize)
        #expect(string(wav, 8..<12) == "WAVE")
        #expect(string(wav, 12..<16) == "fmt ")
        #expect(uint32(wav, 16) == 16)
        #expect(uint16(wav, 20) == 1)
        #expect(uint16(wav, 22) == 1)
        #expect(uint32(wav, 24) == 16000)
        #expect(uint32(wav, 28) == 32000)
        #expect(uint16(wav, 32) == 2)
        #expect(uint16(wav, 34) == 16)
        #expect(string(wav, 36..<40) == "data")
        #expect(uint32(wav, 40) == dataSize)
    }

    @Test func sampleCountAfterResample() {
        let wav = WAVEncoder.encode(samples: SignalFixtures.sine(count: 48000, sampleRate: 48000), sampleRate: 48000)
        #expect(wav.count == 44 + 16000 * 2)
        #expect(PCMReference.int16LE(wav.dropFirst(44)).count == 16000)
    }

    @Test func emptyInputYieldsHeaderOnly() {
        let wav = WAVEncoder.encode(samples: [], sampleRate: 48000)
        #expect(wav.count == 44)
        #expect(uint32(wav, 40) == 0)
        #expect(uint32(wav, 4) == 36)
    }
}
