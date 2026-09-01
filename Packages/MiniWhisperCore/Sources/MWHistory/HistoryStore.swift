import Foundation
import MWSupport

/// The pipeline's seam over history: a delivered dictation is all it records (F29).
public protocol HistoryRecording: Sendable {
    func append(_ entry: HistoryEntry) async throws
}

/// `history.jsonl`: one JSON object per line, loaded once into memory, appended on new
/// entries and rewritten wholesale on delete/clear/prune (design §5.3). Entries older than
/// `retention()` days are dropped after every append; retention 0 deletes the file and
/// disables writes (F29). The URL is always injected — the store never derives a path.
public actor HistoryStore: HistoryRecording {
    private let url: URL
    private let retention: @Sendable () -> Int
    private let now: @Sendable () -> Date
    private var cache: [HistoryEntry]?

    public init(
        url: URL,
        retention: @escaping @Sendable () -> Int,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.url = url
        self.retention = retention
        self.now = now
    }

    public func append(_ entry: HistoryEntry) throws {
        guard retention() > 0 else { return try disable() }
        var all = loaded()
        all.append(entry)
        let kept = withinRetention(all)
        if kept.count == all.count {
            try appendLine(entry)
            cache = all
        } else {
            try rewrite(kept)
        }
    }

    public func entries() -> [HistoryEntry] {
        loaded()
    }

    public func delete(id: String) throws {
        try rewrite(loaded().filter { $0.id != id })
    }

    public func clear() throws {
        try rewrite([])
    }

    public func prune() throws {
        guard retention() > 0 else { return try disable() }
        try rewrite(withinRetention(loaded()))
    }

    /// Case-insensitive substring match on the transcript; an empty query matches everything.
    public func search(_ query: String) -> [HistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return loaded() }
        return loaded().filter { $0.text.range(of: query, options: .caseInsensitive) != nil }
    }

    private func withinRetention(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        let cutoff = now().addingTimeInterval(-Double(retention()) * 86_400)
        return entries.filter { $0.timestamp >= cutoff }
    }

    private func loaded() -> [HistoryEntry] {
        if let cache { return cache }
        let entries = readFile()
        cache = entries
        return entries
    }

    private func readFile() -> [HistoryEntry] {
        guard let data = FileManager.default.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        var entries: [HistoryEntry] = []
        for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let entry = try? decoder.decode(HistoryEntry.self, from: Data(line.utf8)) else {
                // The text itself is never logged (design §5.8); the line is dropped by the
                // next rewrite (§5.7).
                Log.config.warning("history: skipped unreadable line")
                continue
            }
            entries.append(entry)
        }
        return entries
    }

    private func disable() throws {
        cache = []
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func rewrite(_ entries: [HistoryEntry]) throws {
        let encoder = JSONEncoder()
        var data = Data()
        for entry in entries {
            data.append(try encoder.encode(entry))
            data.append(0x0A)
        }
        try writeWholeFile(data)
        cache = entries
    }

    private func appendLine(_ entry: HistoryEntry) throws {
        var data = try JSONEncoder().encode(entry)
        data.append(0x0A)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return try writeWholeFile(data)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func writeWholeFile(_ data: Data) throws {
        try data.write(to: url, options: .atomic)
        // An atomic write replaces the inode, so 0600 is reapplied every time (design §5.8).
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
