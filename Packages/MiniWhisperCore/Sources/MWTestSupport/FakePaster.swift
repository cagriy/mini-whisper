import Foundation
import MWConfig
import MWPaste

/// `Pasting` without a pasteboard or key events: records each delivery and can fail
/// on demand.
public final class FakePaster: Pasting, @unchecked Sendable {
    public struct Call: Sendable {
        public let text: String
        public let pid: pid_t
        public let submit: SubmitKey?
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let failure: (any Error)?

    public init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    public var calls: [Call] { lock.withLock { recorded } }
    public var pasted: [String] { calls.map(\.text) }

    public func paste(_ text: String, into pid: pid_t, submit: SubmitKey?) async throws {
        lock.withLock { recorded.append(Call(text: text, pid: pid, submit: submit)) }
        if let failure { throw failure }
    }
}
