import Foundation
import MWConfig
import MWCorrections
import MWStreaming

/// A `MeetingEngineProviding` that hands out a fresh `FakeStreamingEngine` per session
/// and records what each was asked for, so reconnect and rollover tests can drive every
/// session's sink.
public final class FakeMeetingEngineProvider: MeetingEngineProviding, @unchecked Sendable {
    public struct Call: Sendable, Equatable {
        public var engine: MeetingEngine
        public var key: String
        public var hints: RecognitionHints
    }

    private let lock = NSLock()
    private var made: [(call: Call, engine: FakeStreamingEngine)] = []

    public init() {}

    public var calls: [Call] { lock.withLock { made.map(\.call) } }
    /// Every engine handed out, oldest first.
    public var engines: [FakeStreamingEngine] { lock.withLock { made.map(\.engine) } }

    public func makeMeeting(_ engine: MeetingEngine, key: String, hints: RecognitionHints) -> any StreamingEngine {
        let session = FakeStreamingEngine()
        lock.withLock { made.append((Call(engine: engine, key: key, hints: hints), session)) }
        return session
    }
}
