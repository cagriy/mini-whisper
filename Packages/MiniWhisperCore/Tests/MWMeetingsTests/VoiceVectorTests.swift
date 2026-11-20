import Foundation
import Testing

import MWMeetings

@Suite struct VoiceVectorTests {
    private func unit(_ index: Int) -> VoiceVector {
        var values = [Float](repeating: 0, count: VoiceVector.dimension)
        values[index] = 1
        return VoiceVector(values)
    }

    @Test func encodesAsBase64OfLittleEndianFloat32() throws {
        let values = (0..<VoiceVector.dimension).map { $0 == 0 ? Float(1) : Float(sin(Double($0))) }
        let vector = VoiceVector(values)

        let json = String(decoding: try MeetingCoding.encoder().encode(vector), as: UTF8.self)

        #expect(json.first == "\"" && json.last == "\"")
        let bytes = try #require(Data(base64Encoded: String(json.dropFirst().dropLast())))
        #expect(bytes.count == VoiceVector.dimension * 4)
        #expect(Array(bytes.prefix(4)) == [0x00, 0x00, 0x80, 0x3F])  // 1.0, little-endian
        #expect(try MeetingCoding.decoder().decode(VoiceVector.self, from: Data(json.utf8)) == vector)
    }

    @Test func aStringOfTheWrongLengthFailsToDecode() {
        let short = Data(count: (VoiceVector.dimension - 1) * 4).base64EncodedString()
        let ragged = Data(count: VoiceVector.dimension * 4 + 2).base64EncodedString()

        for text in [short, ragged, "not base64"] {
            #expect(throws: DecodingError.self) {
                try MeetingCoding.decoder().decode(VoiceVector.self, from: Data("\"\(text)\"".utf8))
            }
        }
    }

    @Test func cosineOfParallelIsOneAndOrthogonalZero() {
        let scaled = VoiceVector(unit(3).values.map { $0 * 4 })

        #expect(abs(unit(3).cosine(scaled) - 1) < 1e-9)
        #expect(abs(unit(3).cosine(unit(7))) < 1e-9)
        #expect(unit(3).cosine(VoiceVector([Float](repeating: 0, count: VoiceVector.dimension))) == 0)
    }

    @Test func weightedCombineIsUnitLengthAndLeansToTheLongerPart() throws {
        let combined = try #require(VoiceVector.combine([(unit(0), seconds: 30), (unit(1), seconds: 10)]))

        let length = sqrt(combined.values.reduce(0) { $0 + Double($1) * Double($1) })
        #expect(abs(length - 1) < 1e-6)
        #expect(combined.cosine(unit(0)) > combined.cosine(unit(1)))
        #expect(abs(combined.cosine(unit(0)) - 3 / sqrt(10)) < 1e-6)
    }

    @Test func combineOfNothingIsNil() {
        #expect(VoiceVector.combine([]) == nil)
    }

    @Test func normalisedHasUnitLength() {
        let vector = VoiceVector(unit(2).values.enumerated().map { $0.offset == 5 ? 3 : $0.element * 4 })

        let normalised = vector.normalised
        #expect(abs(normalised.values[2] - 0.8) < 1e-6)
        #expect(abs(normalised.values[5] - 0.6) < 1e-6)
    }
}
