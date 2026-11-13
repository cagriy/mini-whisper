import Foundation
import MWTranscription

/// Summaries without the network: returns a canned result (or throws) and records the
/// system and user text it was given. `queue` answers the first calls, in order; `hold()`
/// keeps every call in flight until `release()`.
public final class FakeSummarizer: Summarizing, @unchecked Sendable {
    public struct Call: Sendable, Equatable {
        public let system: String
        public let user: String
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let result: SummaryResult
    private let failure: (any Error)?
    private var queue: [SummaryResult]
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(
        result: SummaryResult = SummaryResult(text: ""), failure: (any Error)? = nil, queue: [SummaryResult] = []
    ) {
        self.result = result
        self.failure = failure
        self.queue = queue
    }

    public var calls: [Call] { lock.withLock { recorded } }

    public func hold() {
        lock.withLock { held = true }
    }

    public func release() {
        let resumed = lock.withLock {
            held = false
            defer { waiting = [] }
            return waiting
        }
        resumed.forEach { $0.resume() }
    }

    public func summarise(system: String, user: String) async throws -> SummaryResult {
        lock.withLock { recorded.append(Call(system: system, user: user)) }
        await withCheckedContinuation { continuation in
            let passes = lock.withLock {
                if held { waiting.append(continuation) }
                return !held
            }
            if passes { continuation.resume() }
        }
        if let queued = lock.withLock({ queue.isEmpty ? nil : queue.removeFirst() }) { return queued }
        if let failure { throw failure }
        return result
    }
}
