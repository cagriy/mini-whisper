import Foundation
import MWTestSupport
import Testing

import MWStreaming

@Suite struct FakeWebSocketConnectionTests {
    /// A `send` landing between `receive()` deciding to wait and parking must still wake it;
    /// a lost wakeup hangs every replay that ends on `await_client`.
    @Test func sendRacingAWaitingReceiveIsNeverLost() async throws {
        for _ in 0..<20000 {
            let connection = FakeWebSocketConnection(
                script: FixtureScript(steps: [.awaitClient(.type("ping")), .server(#"{"type":"pong"}"#)]),
                clock: VirtualClock()
            )
            async let reply = connection.receive()
            try await connection.send(.text(#"{"type":"ping"}"#))
            #expect(try await reply == .text(#"{"type":"pong"}"#))
        }
    }
}
