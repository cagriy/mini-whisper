import Foundation
import MWHistory

/// In-memory `HistoryRecording`: records what the pipeline delivered without touching disk.
public final class FakeHistoryStore: HistoryRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [HistoryEntry] = []

    public init() {}

    public var appended: [HistoryEntry] { lock.withLock { storage } }

    public func append(_ entry: HistoryEntry) async throws {
        lock.withLock { storage.append(entry) }
    }
}
