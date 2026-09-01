import Foundation
import MWSupport
import MWTranscription

/// Cleanup without the network: returns a canned result and records the text and
/// prompt it was given.
public final class FakeCleaner: Cleaner, @unchecked Sendable {
    public struct Call: Sendable {
        public let text: String
        public let prompt: String
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let text: String
    private let usage: TokenUsage
    private let failure: (any Error)?

    public init(text: String = "", usage: TokenUsage = TokenUsage(), failure: (any Error)? = nil) {
        self.text = text
        self.usage = usage
        self.failure = failure
    }

    public var calls: [Call] { lock.withLock { recorded } }

    public func clean(_ text: String, prompt: String) async throws -> (String, TokenUsage) {
        lock.withLock { recorded.append(Call(text: text, prompt: prompt)) }
        if let failure { throw failure }
        return (self.text, usage)
    }
}
