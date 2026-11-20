import Foundation
import MWConfig

/// What one server message produced: transcript emissions in order, plus any token
/// usage the event carried.
public struct AdapterEmitter: Sendable, Equatable {
    public enum Emission: Sendable, Equatable {
        case partial(String)
        case final(String)
        case segment(TranscriptSegment)
        case speakerRevision([SpeakerRevision])
        case sessionLimit(SessionLimit)
        case speakers([ProviderSpeaker])
        /// The enrolled label and identifier a `speaker_id` warning names; nil when it cannot be read.
        case identifierIgnored(label: String?, identifier: String?)
    }

    public private(set) var emissions: [Emission] = []
    public private(set) var inputTokens = 0
    public private(set) var outputTokens = 0

    public init() {}

    public mutating func partial(_ text: String) { emissions.append(.partial(text)) }
    public mutating func final(_ text: String) { emissions.append(.final(text)) }
    public mutating func segment(_ segment: TranscriptSegment) { emissions.append(.segment(segment)) }
    public mutating func speakerRevision(_ revisions: [SpeakerRevision]) {
        emissions.append(.speakerRevision(revisions))
    }
    public mutating func sessionLimit(_ limit: SessionLimit) { emissions.append(.sessionLimit(limit)) }
    public mutating func speakers(_ speakers: [ProviderSpeaker]) { emissions.append(.speakers(speakers)) }
    public mutating func identifierIgnored(label: String?, identifier: String?) {
        emissions.append(.identifierIgnored(label: label, identifier: identifier))
    }

    public mutating func addTokens(input: Int?, output: Int?) {
        inputTokens += input ?? 0
        outputTokens += output ?? 0
    }
}

/// Everything a cloud provider contributes on top of `WebSocketEngine`'s skeleton:
/// endpoint, message shapes and event parsing (design §5.4).
public protocol EngineAdapter: Sendable {
    var name: EngineName { get }
    var url: URL { get }
    var headers: [String: String] { get }
    /// Sample rate the provider expects; `PCMConverter` resamples every chunk to it.
    var targetRate: Double { get }
    /// Quiet window after the terminal event, for providers whose terminal event can
    /// race trailing transcript events.
    var drainAfterComplete: Duration { get }
    /// Shortest audio chunk the provider accepts; `WebSocketEngine` accumulates
    /// converted audio until it is reached. A requirement, so the generic engine sees
    /// an adapter's own value.
    var minimumChunkSeconds: Double? { get }

    func openMessages() -> [WebSocketMessage]
    mutating func encodeChunk(_ pcm: Data) -> WebSocketMessage
    mutating func endMessages() -> [WebSocketMessage]
    /// Parses one server message; returns `true` when the stream is complete.
    mutating func handle(_ message: WebSocketMessage, emit: inout AdapterEmitter) throws -> Bool
    /// The message for `command`; nil when the provider has none, and the engine drops it.
    func encode(_ command: EngineCommand) -> WebSocketMessage?
}

extension EngineAdapter {
    public var minimumChunkSeconds: Double? { nil }
    public func encode(_ command: EngineCommand) -> WebSocketMessage? { nil }
}
