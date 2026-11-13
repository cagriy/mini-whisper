import Foundation
import MWSupport

/// Sleeps until `wake()`, reporting each sleep's duration.
final class ManualClock: MWSupport.Clock, @unchecked Sendable {
    let sleeps: AsyncStream<Duration>
    private let sleep: AsyncStream<Duration>.Continuation
    private let lock = NSLock()
    private var sleepers: [CheckedContinuation<Void, Never>] = []

    init() {
        (sleeps, sleep) = AsyncStream.makeStream()
    }

    var now: TimeInterval { 0 }

    func sleep(for duration: Duration) async throws {
        await withCheckedContinuation { continuation in
            lock.lock()
            sleepers.append(continuation)
            lock.unlock()
            sleep.yield(duration)
        }
    }

    func wake() {
        lock.lock()
        let woken = sleepers
        sleepers = []
        lock.unlock()
        woken.forEach { $0.resume() }
    }
}
