import Foundation
import MWSupport
import Testing

import MWStreaming

@Suite struct URLSessionWebSocketConnectionTests {
    @Test func closeErrorCarriesCodeAndReason() {
        let error = URLSessionWebSocketConnection.closeError(code: 4005, reason: Data("quota".utf8))

        #expect(error == .closed(code: 4005, reason: "quota"))
        #expect(URLSessionWebSocketConnection.closeError(code: 1011, reason: nil) == .closed(code: 1011, reason: nil))
        #expect(URLSessionWebSocketConnection.closeError(code: 0, reason: nil) == nil)
        #expect(error.map { AnyError($0).description.contains("4005") } == true)
    }
}
