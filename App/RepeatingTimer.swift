import Dispatch
import Foundation

/// A repeating dispatch timer with an idempotent `start`.
///
/// libdispatch aborts the process when a dispatch source is released without having
/// been resumed, so a source is created only inside the critical section that has
/// established it will be stored and resumed. Building one first and dropping it when
/// a timer is already running is what crashed the hotkey watchdog.
final class RepeatingTimer: @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var source: DispatchSourceTimer?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    var isRunning: Bool { lock.withLock { source != nil } }

    /// Starts the timer, or does nothing if it is already running.
    func start(interval: DispatchTimeInterval, handler: @escaping @Sendable () -> Void) {
        let timer: DispatchSourceTimer? = lock.withLock {
            guard source == nil else { return nil }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            source = timer
            return timer
        }
        guard let timer else { return }
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler(handler: handler)
        timer.resume()
    }

    func stop() {
        let timer = lock.withLock { () -> DispatchSourceTimer? in
            defer { source = nil }
            return source
        }
        timer?.cancel()
    }
}
