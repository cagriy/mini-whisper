import Foundation

extension ISO8601DateFormatter {
    /// `2026-09-01T17:38:02Z` — the `ts` format of design §5.3. Formatting and parsing are
    /// thread-safe; the instance is never mutated after this initialiser runs.
    nonisolated(unsafe) static let mwHistory: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// One delivered dictation as stored in `history.jsonl` (F29, design §5.3).
public struct HistoryEntry: Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var text: String
    public var appName: String
    public var bundleID: String?
    /// `nil` for a batch-only dictation.
    public var engine: String?
    public var streamedSeconds: Double
    public var costUSD: Double

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        text: String,
        appName: String,
        bundleID: String? = nil,
        engine: String? = nil,
        streamedSeconds: Double = 0,
        costUSD: Double = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.appName = appName
        self.bundleID = bundleID
        self.engine = engine
        self.streamedSeconds = streamedSeconds
        self.costUSD = costUSD
    }
}

extension HistoryEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp = "ts"
        case text
        case appName = "app_name"
        case bundleID = "bundle_id"
        case engine
        case streamedSeconds = "streamed_seconds"
        case costUSD = "cost_usd"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let stamp = try container.decode(String.self, forKey: .timestamp)
        guard let timestamp = ISO8601DateFormatter.mwHistory.date(from: stamp) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "not an ISO-8601 timestamp"
            )
        }
        self.timestamp = timestamp
        text = try container.decode(String.self, forKey: .text)
        appName = try container.decode(String.self, forKey: .appName)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        engine = try container.decodeIfPresent(String.self, forKey: .engine)
        streamedSeconds = try container.decode(Double.self, forKey: .streamedSeconds)
        costUSD = try container.decode(Double.self, forKey: .costUSD)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ISO8601DateFormatter.mwHistory.string(from: timestamp), forKey: .timestamp)
        try container.encode(text, forKey: .text)
        try container.encode(appName, forKey: .appName)
        // Written as explicit nulls rather than omitted, so every line has every field.
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(engine, forKey: .engine)
        try container.encode(streamedSeconds, forKey: .streamedSeconds)
        try container.encode(costUSD, forKey: .costUSD)
    }
}
