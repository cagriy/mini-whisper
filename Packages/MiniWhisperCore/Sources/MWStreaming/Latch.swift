import Foundation
import MWSupport

/// A latch that many tasks can await and one can raise, cancellation-safe so a racing
/// task group can always unwind. Every engine's `finish` waits on one.
final class Latch: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    private var waiters: [UInt64: CheckedContinuation<Void, Never>] = [:]
    private var cancelled: Set<UInt64> = []
    private var nextID: UInt64 = 0

    func raise() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            raised = true
            defer { waiters.removeAll() }
            return Array(waiters.values)
        }
        for waiter in pending { waiter.resume() }
    }

    func wait() async {
        let id = lock.withLock { () -> UInt64 in
            nextID += 1
            return nextID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in
                    if raised || cancelled.remove(id) != nil { return true }
                    waiters[id] = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                guard let waiter = waiters.removeValue(forKey: id) else {
                    cancelled.insert(id)
                    return nil
                }
                return waiter
            }
            waiter?.resume()
        }
    }

    /// False when `timeout` elapsed on `clock` before the latch was raised.
    func raised(within timeout: Duration, on clock: any Clock) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.wait()
                return true
            }
            group.addTask {
                try? await clock.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
