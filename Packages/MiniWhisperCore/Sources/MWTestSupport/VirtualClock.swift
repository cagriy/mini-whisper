import Foundation
import MWSupport

/// Deterministic `Clock`: time only moves when a test calls `advance(by:)`.
///
/// `waitUntilSleeping(count:)` is the barrier that removes the race between a task
/// registering its sleep and the test advancing past its deadline.
public final class VirtualClock: MWSupport.Clock, @unchecked Sendable {
    private struct Sleeper {
        let id: UInt64
        let wake: TimeInterval
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var currentTime: TimeInterval = 0
    private var sleepers: [Sleeper] = []
    private var arrivalWaiters: [(needed: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var cancelledIDs: Set<UInt64> = []
    private var nextID: UInt64 = 0

    public init() {}

    public var now: TimeInterval {
        lock.withLock { currentTime }
    }

    public func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let id = lock.withLock { () -> UInt64 in
            nextID += 1
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                var resumption: (any Error)??
                var arrived: [CheckedContinuation<Void, Never>] = []
                lock.lock()
                let wake = currentTime + duration.seconds
                if cancelledIDs.remove(id) != nil {
                    resumption = .some(CancellationError())
                } else if wake <= currentTime {
                    resumption = .some(nil)
                } else {
                    sleepers.append(Sleeper(id: id, wake: wake, continuation: continuation))
                    arrived = takeSatisfiedArrivalWaitersLocked()
                }
                lock.unlock()

                for waiter in arrived { waiter.resume() }
                switch resumption {
                case .some(.some(let error)): continuation.resume(throwing: error)
                case .some(.none): continuation.resume()
                case .none: break
                }
            }
        } onCancel: {
            let sleeper = lock.withLock { () -> Sleeper? in
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
                    cancelledIDs.insert(id)
                    return nil
                }
                return sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and resumes every sleeper now due, earliest deadline first.
    public func advance(by seconds: TimeInterval) {
        let due = lock.withLock { () -> [Sleeper] in
            currentTime += seconds
            let ready = sleepers.filter { $0.wake <= currentTime }.sorted { $0.wake < $1.wake }
            sleepers.removeAll { $0.wake <= currentTime }
            return ready
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Suspends until at least `count` tasks are sleeping on this clock.
    public func waitUntilSleeping(count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let satisfied = lock.withLock { () -> Bool in
                guard sleepers.count < count else { return true }
                arrivalWaiters.append((needed: count, continuation: continuation))
                return false
            }
            if satisfied { continuation.resume() }
        }
    }

    private func takeSatisfiedArrivalWaitersLocked() -> [CheckedContinuation<Void, Never>] {
        let satisfied = arrivalWaiters.filter { $0.needed <= sleepers.count }
        arrivalWaiters.removeAll { $0.needed <= sleepers.count }
        return satisfied.map(\.continuation)
    }
}
