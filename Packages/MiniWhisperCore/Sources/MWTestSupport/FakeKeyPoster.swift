import CoreGraphics
import Foundation
import MWPaste

/// Records the key events the paster would post; nothing reaches the window server.
public final class FakeKeyPoster: KeyPoster, @unchecked Sendable {
    public struct Event: Equatable, Sendable {
        public let keyCode: CGKeyCode
        public let flags: CGEventFlags
        public let down: Bool
        public let pid: pid_t

        public init(keyCode: CGKeyCode, flags: CGEventFlags, down: Bool, pid: pid_t) {
            self.keyCode = keyCode
            self.flags = flags
            self.down = down
            self.pid = pid
        }
    }

    private let lock = NSLock()
    private var recorded: [Event] = []

    public init() {}

    public var events: [Event] { lock.withLock { recorded } }

    public func post(keyCode: CGKeyCode, flags: CGEventFlags, down: Bool, pid: pid_t) {
        lock.withLock { recorded.append(Event(keyCode: keyCode, flags: flags, down: down, pid: pid)) }
    }
}
