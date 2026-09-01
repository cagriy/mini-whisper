import Foundation
import MWSupport
import Testing

import MWTranscription

private struct Refusal: Error, LocalizedError {
    var errorDescription: String? { "the network went away" }
}

/// F14's status→message table, verbatim.
@Suite struct APIErrorTests {
    @Test func invalidKeyMessage() {
        #expect(APIError.httpStatus(401).userMessage == "Invalid API key — please update in Settings.")
    }

    @Test func rateLimitedMessage() {
        #expect(APIError.httpStatus(429).userMessage == "Rate limited — please wait and try again.")
    }

    @Test func otherStatusMessage() {
        #expect(APIError.httpStatus(503).userMessage == "API error (503).")
        #expect(APIError.httpStatus(500).userMessage == "API error (500).")
    }

    @Test func transportErrorUsesDescription() {
        #expect(APIError.transport(Refusal()).userMessage == "the network went away")
    }

    /// The pipeline maps every failure through `AnyError` (F14, "other failures → the
    /// error's description"), so these messages must survive that trip.
    @Test func anyErrorReportsTheSameMessage() {
        #expect(AnyError(APIError.httpStatus(429)).description == APIError.httpStatus(429).userMessage)
        #expect(AnyError(APIError.emptyAudio).description == APIError.emptyAudio.userMessage)
    }
}
