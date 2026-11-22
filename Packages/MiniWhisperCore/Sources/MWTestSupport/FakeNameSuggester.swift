import Foundation
import MWTranscription

/// Name suggestions without the network: `answers` reply to the first calls in order, then
/// `otherwise` to every later one. Records each request; `hold()` keeps every call in flight
/// until `release()`, and `waitForRequests(_:)` is the barrier for a call having arrived.
public final class FakeNameSuggester: NameSuggesting, @unchecked Sendable {
    public enum Answer: Sendable {
        case reply(NamingReply)
        case failure(any Error)
    }

    private let lock = NSLock()
    private var recorded: [NamingRequest] = []
    private var answers: [Answer]
    private let otherwise: Answer
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var arrivals: [(needed: Int, continuation: CheckedContinuation<Void, Never>)] = []

    public init(_ answers: [Answer] = [], otherwise: Answer = .reply(NamingReply(suggestions: []))) {
        self.answers = answers
        self.otherwise = otherwise
    }

    public var requests: [NamingRequest] { lock.withLock { recorded } }

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

    /// Suspends until at least `count` requests have been made.
    public func waitForRequests(_ count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let satisfied = lock.withLock {
                guard recorded.count < count else { return true }
                arrivals.append((count, continuation))
                return false
            }
            if satisfied { continuation.resume() }
        }
    }

    public func suggestNames(_ request: NamingRequest) async throws -> NamingReply {
        let arrived = lock.withLock {
            recorded.append(request)
            let ready = arrivals.filter { $0.needed <= recorded.count }
            arrivals.removeAll { $0.needed <= recorded.count }
            return ready.map(\.continuation)
        }
        arrived.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            let passes = lock.withLock {
                if held { waiting.append(continuation) }
                return !held
            }
            if passes { continuation.resume() }
        }
        switch lock.withLock({ answers.isEmpty ? otherwise : answers.removeFirst() }) {
        case .reply(let reply): return reply
        case .failure(let error): throw error
        }
    }
}
