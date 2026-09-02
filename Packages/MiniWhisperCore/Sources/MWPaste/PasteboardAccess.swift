import Foundation

/// Every item on the pasteboard as its type → data map, so a restore puts back exactly
/// what was there rather than plain text only (F25).
public struct PasteboardSnapshot: Equatable, Sendable {
    public let items: [[String: Data]]

    public init(items: [[String: Data]]) {
        self.items = items
    }
}

/// `NSPasteboard.general` behind a seam: `swift test` never touches the real pasteboard.
public protocol PasteboardAccess: Sendable {
    func snapshot() -> PasteboardSnapshot
    /// Replaces the contents with `text` and returns the change count after the write —
    /// the value the restore-if-unchanged rule compares against.
    func write(_ text: String) -> Int
    var changeCount: Int { get }
    func restore(_ snapshot: PasteboardSnapshot)
}
