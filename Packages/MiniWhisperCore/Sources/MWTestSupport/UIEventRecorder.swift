import Foundation
import MWPipeline

/// Collects the pipeline's `UIEvent`s in order. `emit` is the closure the pipeline takes,
/// so a test can pass the recorder straight in.
public final class UIEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UIEvent] = []

    public init() {}

    public var events: [UIEvent] { lock.withLock { storage } }

    public var emit: @Sendable (UIEvent) -> Void {
        { [self] event in lock.withLock { storage.append(event) } }
    }
}
