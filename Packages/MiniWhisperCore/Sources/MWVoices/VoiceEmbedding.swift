import MWMeetings

/// Turns one window of 16 kHz speech into a voice vector.
public protocol VoiceEmbedding: Sendable {
    /// Loads the model; later calls return at once.
    func prepare() async throws
    func embed(_ window: [Float]) async throws -> VoiceVector
}

public enum VoiceEmbeddingError: Error, Equatable, Sendable {
    case modelUnavailable
    case badWindow
}
