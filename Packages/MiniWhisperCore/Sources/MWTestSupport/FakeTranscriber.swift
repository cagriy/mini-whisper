import Foundation
import MWSupport
import MWTranscription

/// Batch transcription without the network: returns a canned result and records what
/// the pipeline asked it to transcribe.
public final class FakeTranscriber: Transcriber, @unchecked Sendable {
    public struct Call: Sendable {
        public let wav: Data
        public let instructions: String
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

    public func transcribe(wav: Data, instructions: String) async throws -> (String, TokenUsage) {
        lock.withLock { recorded.append(Call(wav: wav, instructions: instructions)) }
        if let failure { throw failure }
        return (text, usage)
    }
}
