import Foundation
import MWPipeline

/// Records the sounds the pipeline asked for, in order.
public final class FakeSoundPlayer: SoundPlaying, @unchecked Sendable {
    public enum Sound: String, Sendable, Equatable {
        case on
        case off
        case tick
    }

    private let lock = NSLock()
    private var storage: [Sound] = []
    private var waiters: [(needed: Int, continuation: CheckedContinuation<Void, Never>)] = []

    public init() {}

    public var played: [Sound] { lock.withLock { storage } }

    public func playOn() { append(.on) }
    public func playOff() { append(.off) }
    public func playTick() { append(.tick) }

    /// Suspends until at least `count` sounds have been asked for: the barrier for a sound
    /// played by a timer task, which resumes off the caller's executor.
    public func waitUntilPlayed(count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let satisfied = lock.withLock { () -> Bool in
                guard storage.count < count else { return true }
                waiters.append((needed: count, continuation: continuation))
                return false
            }
            if satisfied { continuation.resume() }
        }
    }

    private func append(_ sound: Sound) {
        let ready = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            storage.append(sound)
            let satisfied = waiters.filter { $0.needed <= storage.count }
            waiters.removeAll { $0.needed <= storage.count }
            return satisfied.map(\.continuation)
        }
        for waiter in ready { waiter.resume() }
    }
}
