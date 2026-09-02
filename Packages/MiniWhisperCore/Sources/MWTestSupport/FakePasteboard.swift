import Foundation
import MWPaste

/// In-memory pasteboard modelling the change count the restore-if-unchanged rule
/// depends on, and recording what was written and restored.
public final class FakePasteboard: PasteboardAccess, @unchecked Sendable {
    private static let plainText = "public.utf8-plain-text"

    private let lock = NSLock()
    private var current: PasteboardSnapshot
    private var count = 0
    private var writes: [String] = []
    private var restores: [PasteboardSnapshot] = []

    public init(contents: PasteboardSnapshot) {
        current = contents
    }

    public var contents: PasteboardSnapshot { lock.withLock { current } }
    public var written: [String] { lock.withLock { writes } }
    public var restored: [PasteboardSnapshot] { lock.withLock { restores } }

    /// The user copying something else during the restore window.
    public func changeExternally() {
        lock.withLock {
            current = PasteboardSnapshot(items: [[Self.plainText: Data("elsewhere".utf8)]])
            count += 1
        }
    }

    public func snapshot() -> PasteboardSnapshot { contents }

    public func write(_ text: String) -> Int {
        lock.withLock {
            writes.append(text)
            current = PasteboardSnapshot(items: [[Self.plainText: Data(text.utf8)]])
            count += 1
            return count
        }
    }

    public var changeCount: Int { lock.withLock { count } }

    public func restore(_ snapshot: PasteboardSnapshot) {
        lock.withLock {
            restores.append(snapshot)
            current = snapshot
            count += 1
        }
    }
}
