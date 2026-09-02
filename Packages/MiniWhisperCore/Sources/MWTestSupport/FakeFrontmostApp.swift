import Foundation
import MWPipeline

/// The frontmost application as a value a test sets (F17).
public final class FakeFrontmostApp: FrontmostAppProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: PasteTarget?

    public init(_ target: PasteTarget? = nil) {
        storage = target
    }

    public var target: PasteTarget? {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    public func frontmost() -> PasteTarget? { lock.withLock { storage } }
}
