import Foundation
import Testing
@testable import MWSupport
import MWTestSupport

@Suite struct VirtualClockTests {
    @Test func sleepResumesWhenAdvancedPast() async throws {
        let clock = VirtualClock()
        let task = Task { try await clock.sleep(for: .seconds(1.5)) }
        await clock.waitUntilSleeping()

        clock.advance(by: 1.5)
        try await task.value

        #expect(clock.now == 1.5)
    }

    @Test func cancelledSleepThrows() async throws {
        let clock = VirtualClock()
        let task = Task { try await clock.sleep(for: .seconds(10)) }
        await clock.waitUntilSleeping()

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.now == 0)
    }

    @Test func nowAdvancesMonotonically() {
        let clock = VirtualClock()
        #expect(clock.now == 0)

        clock.advance(by: 0.25)
        clock.advance(by: 0.75)

        let asProtocol: any MWSupport.Clock = clock
        #expect(asProtocol.now == 1.0)
    }
}
