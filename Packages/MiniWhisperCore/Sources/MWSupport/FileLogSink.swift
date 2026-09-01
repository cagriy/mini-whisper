import Foundation

extension ISO8601DateFormatter {
    /// Formatting on `ISO8601DateFormatter` is thread-safe; the instance is never mutated
    /// after this initialiser runs.
    nonisolated(unsafe) public static let mwLog: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// Appends `<ISO ts> <LEVEL> <category> <message>` lines to a file created 0600 on first
/// write. Installed only under `--debug` (F38).
public final class FileLogSink: LogSink, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var handle: FileHandle?

    public init(url: URL) {
        self.url = url
    }

    deinit {
        try? handle?.close()
    }

    public func write(_ record: LogRecord) {
        let line = "\(ISO8601DateFormatter.mwLog.string(from: record.timestamp)) "
            + "\(record.level.rawValue) \(record.category) \(record.message)\n"
        guard let data = line.data(using: .utf8) else { return }
        lock.withLock {
            if handle == nil {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(
                        atPath: url.path,
                        contents: nil,
                        attributes: [.posixPermissions: 0o600]
                    )
                }
                handle = try? FileHandle(forWritingTo: url)
                try? handle?.seekToEnd()
            }
            try? handle?.write(contentsOf: data)
        }
    }
}
