import Foundation
import MWStreaming

/// Collects everything an engine reports so tests can assert on the sequence.
public final class RecordingSink: TranscriptSink, @unchecked Sendable {
    private struct Storage {
        var partials: [String] = []
        var finals: [String] = []
        var errors: [any Error] = []
    }

    private let lock = NSLock()
    private var storage = Storage()

    public init() {}

    public func onPartial(_ text: String) { lock.withLock { storage.partials.append(text) } }
    public func onFinal(_ text: String) { lock.withLock { storage.finals.append(text) } }
    public func onEngineError(_ error: any Error) { lock.withLock { storage.errors.append(error) } }

    public var partials: [String] { lock.withLock { storage.partials } }
    public var finals: [String] { lock.withLock { storage.finals } }
    public var errors: [any Error] { lock.withLock { storage.errors } }
}
