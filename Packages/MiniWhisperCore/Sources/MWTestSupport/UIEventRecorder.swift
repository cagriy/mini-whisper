import Foundation
import MWPipeline

/// Collects the pipeline's `UIEvent`s in order. `emit` is the closure the pipeline takes,
/// so a test can pass the recorder straight in.
public final class UIEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UIEvent] = []

    public init() {}

    public var events: [UIEvent] { lock.withLock { storage } }

    /// Every delivered dictation in order, so a test asserts on the payload rather than
    /// pattern-matching `.result` by hand.
    public var results: [DeliveredDictation] {
        events.compactMap { if case .result(let dictation) = $0 { dictation } else { nil } }
    }

    public var emit: @Sendable (UIEvent) -> Void {
        { [self] event in lock.withLock { storage.append(event) } }
    }
}
