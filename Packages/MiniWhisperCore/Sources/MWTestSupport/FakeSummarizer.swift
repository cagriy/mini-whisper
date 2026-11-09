import Foundation
import MWTranscription

/// Summaries without the network: returns a canned result (or throws) and records the
/// system and user text it was given.
public final class FakeSummarizer: Summarizing, @unchecked Sendable {
    public struct Call: Sendable, Equatable {
        public let system: String
        public let user: String
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let result: SummaryResult
    private let failure: (any Error)?

    public init(result: SummaryResult = SummaryResult(text: ""), failure: (any Error)? = nil) {
        self.result = result
        self.failure = failure
    }

    public var calls: [Call] { lock.withLock { recorded } }

    public func summarise(system: String, user: String) async throws -> SummaryResult {
        lock.withLock { recorded.append(Call(system: system, user: user)) }
        if let failure { throw failure }
        return result
    }
}
