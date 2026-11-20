import CoreML
import Foundation
import MWMeetings
import MWTestSupport
import Testing

import MWVoices

/// R6: the model reads one 10 s window in each of its three rows under all-ones masks, and row 0
/// of its output is the voice. The bundled model itself is exercised by `AppTests/VoiceModelTests`.
@Suite struct CoreMLVoiceEmbedderTests {
    private func floats(_ array: MLMultiArray) -> [Float] {
        (0..<array.count).map { array[$0].floatValue }
    }

    @Test func theInputFillsEveryRowWithTheWindowAndAnAllOnesMask() throws {
        let window = (0..<VoiceWindow.windowSamples).map { Float($0 % 977) / 977 }
        let input = try CoreMLVoiceEmbedder.input(window)

        let waveform = try #require(input.featureValue(for: "waveform")?.multiArrayValue)
        #expect(waveform.shape == [3, 160_000])
        #expect(waveform.dataType == .float32)
        let rows = floats(waveform)
        for row in 0..<3 {
            #expect(Array(rows[row * 160_000..<(row + 1) * 160_000]) == window)
        }

        let mask = try #require(input.featureValue(for: "mask")?.multiArrayValue)
        #expect(mask.shape == [3, 589])
        #expect(mask.dataType == .float32)
        #expect(floats(mask).allSatisfy { $0 == 1 })
    }

    @Test func aWindowOfTheWrongLengthIsRejected() async {
        for count in [0, VoiceWindow.windowSamples - 1, VoiceWindow.windowSamples + 1] {
            let window = [Float](repeating: 0.1, count: count)
            #expect(throws: VoiceEmbeddingError.badWindow) { try CoreMLVoiceEmbedder.input(window) }
            await #expect(throws: VoiceEmbeddingError.badWindow) {
                try await CoreMLVoiceEmbedder(modelURL: nil).embed(window)
            }
        }
    }

    @Test func outputRowZeroIsNormalised() throws {
        let embedding = try MLMultiArray(shape: [3, 256], dataType: .float32)
        for index in 0..<embedding.count { embedding[index] = 7 }
        embedding[[0, 0]] = 3
        embedding[[0, 1]] = 4
        for column in 2..<256 { embedding[[0, NSNumber(value: column)]] = 0 }

        let vector = try CoreMLVoiceEmbedder.vector(from: embedding)

        #expect(vector == .padded([0.6, 0.8]))
    }

    @Test func anOutputOfAnotherShapeIsRejected() throws {
        let embedding = try MLMultiArray(shape: [3, 192], dataType: .float32)
        #expect(throws: VoiceEmbeddingError.modelUnavailable) { try CoreMLVoiceEmbedder.vector(from: embedding) }
    }

    @Test func withoutAModelPrepareThrows() async throws {
        let window = [Float](repeating: 0.1, count: VoiceWindow.windowSamples)
        let directory = try TempDirectory()
        let missing = directory.url.appendingPathComponent("wespeaker_v2.mlmodelc")

        for embedder in [CoreMLVoiceEmbedder(modelURL: nil), CoreMLVoiceEmbedder(modelURL: missing)] {
            await #expect(throws: VoiceEmbeddingError.modelUnavailable) { try await embedder.prepare() }
            await #expect(throws: VoiceEmbeddingError.modelUnavailable) { try await embedder.embed(window) }
        }
    }
}
