import CoreML
import Foundation
import MWMeetings
import MWSupport

/// R6: the bundled WeSpeaker model. It reads only row 0's clip, so every row carries the same
/// window under an all-ones mask, and row 0 of the output, L2-normalised, is the voice.
public final class CoreMLVoiceEmbedder: VoiceEmbedding, @unchecked Sendable {
    private static let rows = 3
    private static let frames = 589

    private let modelURL: URL?
    /// Guards the load and every prediction: synchronous predictions on one model are serialised.
    private let lock = NSLock()
    private var loaded: Result<MLModel, VoiceEmbeddingError>?

    /// `nil` when the app bundle holds no model; every call then throws `.modelUnavailable`.
    public init(modelURL: URL?) {
        self.modelURL = modelURL
    }

    public func prepare() async throws {
        _ = try lock.withLock { try model() }
    }

    public func embed(_ window: [Float]) async throws -> VoiceVector {
        let input = try Self.input(window)
        return try lock.withLock {
            let output = try model().prediction(from: input)
            guard let embedding = output.featureValue(for: "embedding")?.multiArrayValue else {
                throw VoiceEmbeddingError.modelUnavailable
            }
            return try Self.vector(from: embedding)
        }
    }

    /// The model's input for one window of exactly `VoiceWindow.windowSamples`.
    public static func input(_ window: [Float]) throws -> MLFeatureProvider {
        guard window.count == VoiceWindow.windowSamples else { throw VoiceEmbeddingError.badWindow }
        let waveform = try filled(rows: rows, columns: window.count) { row in
            _ = row.update(fromContentsOf: window)
        }
        let mask = try filled(rows: rows, columns: frames) { row in
            row.update(repeating: 1)
        }
        return try MLDictionaryFeatureProvider(dictionary: ["waveform": waveform, "mask": mask])
    }

    /// Row 0 of a `[3, 256]` output, normalised.
    public static func vector(from embedding: MLMultiArray) throws -> VoiceVector {
        guard embedding.shape == [NSNumber(value: rows), NSNumber(value: VoiceVector.dimension)] else {
            throw VoiceEmbeddingError.modelUnavailable
        }
        let row = (0..<VoiceVector.dimension).map { embedding[[0, NSNumber(value: $0)]].floatValue }
        return VoiceVector(row).normalised
    }

    private static func filled(
        rows: Int, columns: Int, _ fill: (UnsafeMutableBufferPointer<Float>) -> Void
    ) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [NSNumber(value: rows), NSNumber(value: columns)], dataType: .float32)
        array.withUnsafeMutableBufferPointer(ofType: Float.self) { pointer, strides in
            for row in 0..<rows {
                let start = row * strides[0]
                fill(UnsafeMutableBufferPointer(rebasing: pointer[start..<start + columns]))
            }
        }
        return array
    }

    /// Called under `lock`. The outcome is kept, so a missing model fails at once from then on.
    private func model() throws -> MLModel {
        let outcome = loaded ?? load()
        loaded = outcome
        return try outcome.get()
    }

    private func load() -> Result<MLModel, VoiceEmbeddingError> {
        guard let modelURL else { return .failure(.modelUnavailable) }
        let started = Date()
        do {
            let model = try MLModel(contentsOf: modelURL)
            Log.voice.info("model loaded in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
            return .success(model)
        } catch {
            Log.voice.warning("model failed to load: \(error.localizedDescription)")
            return .failure(.modelUnavailable)
        }
    }
}
