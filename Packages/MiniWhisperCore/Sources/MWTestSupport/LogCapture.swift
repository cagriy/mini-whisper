import Foundation
import MWSupport

/// Async mutex: `acquire` suspends rather than blocking a cooperative thread.
private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let proceed = lock.withLock { () -> Bool in
                guard !busy else {
                    waiters.append(continuation)
                    return false
                }
                busy = true
                return true
            }
            if proceed { continuation.resume() }
        }
    }

    func release() {
        let next = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            guard !waiters.isEmpty else {
                busy = false
                return nil
            }
            return waiters.removeFirst()
        }
        next?.resume()
    }
}

/// `Log`'s sink list is process-wide, so suites that assert on it must not run
/// concurrently — every log-observing test goes through this gate.
public enum LogCapture {
    private static let gate = AsyncGate()

    public static func run<T>(
        debug: Bool = false,
        sinks: [any LogSink],
        _ body: () async throws -> T
    ) async rethrows -> T {
        await gate.acquire()
        defer {
            Log.configure(debug: false, sinks: [])
            gate.release()
        }
        Log.configure(debug: debug, sinks: sinks)
        return try await body()
    }
}
