import Dispatch
import Foundation
import Testing

@testable import MiniWhisper

/// `RepeatingTimer` exists because libdispatch traps — it does not throw — when a
/// dispatch source is released without ever being resumed. The watchdog reached that
/// state by building a source on every tick and dropping it whenever one was already
/// running, which killed the app about 100 ms after the first hotkey press.
@Suite struct RepeatingTimerTests {
    private func makeTimer() -> RepeatingTimer {
        RepeatingTimer(queue: DispatchQueue(label: "test.repeating-timer"))
    }

    @Test func repeatedStartNeverBuildsASourceItWillNotResume() {
        let timer = makeTimer()
        defer { timer.stop() }

        // Each redundant start must be a no-op. Against the original watchdog this
        // aborts the process on the second call rather than failing an expectation.
        for _ in 0..<50 {
            timer.start(interval: .seconds(60)) {}
        }

        #expect(timer.isRunning)
    }

    @Test func stopLeavesTheTimerRestartable() {
        let timer = makeTimer()

        timer.start(interval: .seconds(60)) {}
        #expect(timer.isRunning)

        timer.stop()
        #expect(!timer.isRunning)

        timer.start(interval: .seconds(60)) {}
        #expect(timer.isRunning)
        timer.stop()
    }

    @Test func stopBeforeStartIsHarmless() {
        let timer = makeTimer()
        timer.stop()
        #expect(!timer.isRunning)
    }

    @Test func firesRepeatedlyUntilStopped() async throws {
        let timer = makeTimer()
        let ticks = OSCounter()

        timer.start(interval: .milliseconds(10)) { ticks.increment() }
        try await Task.sleep(for: .milliseconds(200))
        timer.stop()

        let afterStop = ticks.value
        #expect(afterStop >= 2)

        try await Task.sleep(for: .milliseconds(100))
        #expect(ticks.value == afterStop)
    }
}

/// Minimal thread-safe counter for the firing test.
private final class OSCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
