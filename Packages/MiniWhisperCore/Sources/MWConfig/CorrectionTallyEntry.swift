import Foundation

extension ISO8601DateFormatter {
    /// `2026-09-05T16:07:00Z` — the `history.jsonl` timestamp format. MWHistory's
    /// equivalent is internal to that module. Formatting and parsing are thread-safe;
    /// the instance is never mutated after this initialiser runs.
    nonisolated(unsafe) public static let mwConfig: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// How often one heard phrase has been corrected (R2), in its first-seen spelling.
public struct CorrectionTallyEntry: Equatable, Sendable {
    public var heard: String
    public var count: Int
    public var last: Date

    public init(heard: String, count: Int, last: Date) {
        self.heard = heard
        self.count = count
        self.last = last
    }
}

extension CorrectionTallyEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case heard
        case count
        case last
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        heard = try container.decode(String.self, forKey: .heard)
        count = try container.decode(Int.self, forKey: .count)
        // An unreadable timestamp sorts oldest instead of failing the whole config load.
        let stamp = try container.decodeIfPresent(String.self, forKey: .last) ?? ""
        last = ISO8601DateFormatter.mwConfig.date(from: stamp) ?? .distantPast
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(heard, forKey: .heard)
        try container.encode(count, forKey: .count)
        try container.encode(ISO8601DateFormatter.mwConfig.string(from: last), forKey: .last)
    }
}
