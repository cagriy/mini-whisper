import Foundation
import Testing
@testable import MWSupport

@Suite struct AnyErrorTests {
    private struct Localized: LocalizedError {
        var errorDescription: String? { "Rate limited — please wait and try again." }
    }

    @Test func descriptionPrefersLocalizedDescription() {
        #expect(AnyError(Localized()).description == "Rate limited — please wait and try again.")
    }

    @Test func usesLocalizedDescriptionOfNSError() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )
        #expect(AnyError(error).description == "The Internet connection appears to be offline.")
    }

    @Test func wrapsNSErrorDomainAndCode() {
        let error = NSError(domain: "MWTestDomain", code: 42)
        #expect(AnyError(error).description == "MWTestDomain 42")
    }
}
