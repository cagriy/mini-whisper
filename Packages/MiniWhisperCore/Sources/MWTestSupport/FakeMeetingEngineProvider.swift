import Foundation
import MWConfig
import MWCorrections
import MWStreaming

/// A `MeetingEngineProviding` that hands out a fresh `FakeStreamingEngine` per session
/// and records what each was asked for, so reconnect and rollover tests can drive every
/// session's sink.
public final class FakeMeetingEngineProvider: MeetingEngineProviding, @unchecked Sendable {
    public struct Call: Sendable, Equatable {
        public var engine: MeetingEngine
        public var key: String
        public var hints: RecognitionHints
        public var voices: VoiceSessionConfig?
    }

    private let lock = NSLock()
    private var made: [(call: Call, engine: FakeStreamingEngine)] = []
    private var started = 0
    private var startWaiters: [(needed: Int, continuation: CheckedContinuation<Void, Never>)] = []

    public init() {}

    public var calls: [Call] { lock.withLock { made.map(\.call) } }
    /// Every engine handed out, oldest first.
    public var engines: [FakeStreamingEngine] { lock.withLock { made.map(\.engine) } }

    public func makeMeeting(
        _ engine: MeetingEngine, key: String, hints: RecognitionHints, voices: VoiceSessionConfig?
    ) -> any StreamingEngine {
        let session = FakeStreamingEngine { [weak self] in self?.didStart() }
        lock.withLock { made.append((Call(engine: engine, key: key, hints: hints, voices: voices), session)) }
        return session
    }

    /// Suspends until `count` sessions have been started. A lost session reopens from a timer
    /// task off the caller's actor, so a test awaits it here instead of polling.
    public func waitUntilStarted(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let satisfied = lock.withLock { () -> Bool in
                guard started < count else { return true }
                startWaiters.append((needed: count, continuation: continuation))
                return false
            }
            if satisfied { continuation.resume() }
        }
    }

    private func didStart() {
        let ready = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            started += 1
            let ready = startWaiters.filter { $0.needed <= started }
            startWaiters.removeAll { $0.needed <= started }
            return ready.map(\.continuation)
        }
        for waiter in ready { waiter.resume() }
    }
}
