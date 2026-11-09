import Foundation
import MWStreaming

/// Collects everything an engine reports so tests can assert on the sequence.
public final class RecordingSink: TranscriptSink, @unchecked Sendable {
    private struct Storage {
        var partials: [String] = []
        var finals: [String] = []
        var errors: [any Error] = []
        var segments: [TranscriptSegment] = []
        var revisions: [[SpeakerRevision]] = []
        var limits: [SessionLimit] = []
    }

    private let lock = NSLock()
    private var storage = Storage()

    public init() {}

    public func onPartial(_ text: String) { lock.withLock { storage.partials.append(text) } }
    public func onFinal(_ text: String) { lock.withLock { storage.finals.append(text) } }
    public func onEngineError(_ error: any Error) { lock.withLock { storage.errors.append(error) } }
    public func onSegment(_ segment: TranscriptSegment) { lock.withLock { storage.segments.append(segment) } }
    public func onSpeakerRevision(_ revisions: [SpeakerRevision]) {
        lock.withLock { storage.revisions.append(revisions) }
    }
    public func onSessionLimit(_ limit: SessionLimit) { lock.withLock { storage.limits.append(limit) } }

    public var partials: [String] { lock.withLock { storage.partials } }
    public var finals: [String] { lock.withLock { storage.finals } }
    public var errors: [any Error] { lock.withLock { storage.errors } }
    public var segments: [TranscriptSegment] { lock.withLock { storage.segments } }
    public var revisions: [[SpeakerRevision]] { lock.withLock { storage.revisions } }
    public var limits: [SessionLimit] { lock.withLock { storage.limits } }
}
