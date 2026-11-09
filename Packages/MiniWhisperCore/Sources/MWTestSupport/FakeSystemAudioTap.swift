import AVFAudio
import Foundation
import MWAudio

/// `SystemAudioTapping` without Core Audio: a test pushes buffers and events by hand.
public final class FakeSystemAudioTap: SystemAudioTapping, @unchecked Sendable {
    private struct State {
        var handler: (@Sendable (AVAudioPCMBuffer) -> Void)?
        var startCount = 0
        var stopCount = 0
        var startError: (any Error)?
    }

    private let lock = NSLock()
    private var state = State()
    private let continuation: AsyncStream<SystemAudioTapEvent>.Continuation

    public let events: AsyncStream<SystemAudioTapEvent>

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    deinit {
        continuation.finish()
    }

    public var startCount: Int { lock.withLock { state.startCount } }
    public var stopCount: Int { lock.withLock { state.stopCount } }

    public var startError: (any Error)? {
        get { lock.withLock { state.startError } }
        set { lock.withLock { state.startError = newValue } }
    }

    public func start(_ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        try lock.withLock {
            if let error = state.startError { throw error }
            state.startCount += 1
            state.handler = handler
        }
    }

    public func stop() {
        lock.withLock {
            state.stopCount += 1
            state.handler = nil
        }
    }

    /// Runs the handler on the caller's thread, as the real IOProc does on its own.
    public func push(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { state.handler }?(buffer)
    }

    public func send(_ event: SystemAudioTapEvent) {
        continuation.yield(event)
    }
}

public final class FakeSystemAudioTapFactory: SystemAudioTapFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var pids: [pid_t] = []

    /// Returned by every `make`; `nil` plays a system below macOS 14.2.
    public let tap: FakeSystemAudioTap?

    public init(tap: FakeSystemAudioTap? = FakeSystemAudioTap()) {
        self.tap = tap
    }

    public var excludedPIDs: [pid_t] { lock.withLock { pids } }

    public func make(excluding pid: pid_t) -> (any SystemAudioTapping)? {
        lock.withLock { pids.append(pid) }
        return tap
    }
}
