import Foundation
import MWSupport

/// Collects log records in memory so tests can assert on what was (and was not) logged.
public final class CapturingLogSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LogRecord] = []

    public init() {}

    public func write(_ record: LogRecord) {
        lock.withLock { storage.append(record) }
    }

    public var records: [LogRecord] {
        lock.withLock { storage }
    }

    /// `<LEVEL> <category> <message>` — the file-sink line without its timestamp.
    public var lines: [String] {
        records.map { "\($0.level.rawValue) \($0.category) \($0.message)" }
    }
}
