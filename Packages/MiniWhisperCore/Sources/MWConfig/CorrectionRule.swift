import Foundation

/// One remembered correction (R1). `bundleID == nil` means All apps.
public struct CorrectionRule: Equatable, Sendable {
    public var id: String
    public var heard: String
    public var write: String
    public var soundsLike: [String]
    public var bundleID: String?
    public var enabled: Bool

    public init(
        id: String = UUID().uuidString,
        heard: String,
        write: String,
        soundsLike: [String] = [],
        bundleID: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.heard = heard
        self.write = write
        self.soundsLike = soundsLike
        self.bundleID = bundleID
        self.enabled = enabled
    }
}

extension CorrectionRule: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case heard
        case write
        case soundsLike = "sounds_like"
        case bundleID = "bundle_id"
        case enabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        heard = try container.decode(String.self, forKey: .heard)
        write = try container.decode(String.self, forKey: .write)
        soundsLike = try container.decodeIfPresent([String].self, forKey: .soundsLike) ?? []
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(heard, forKey: .heard)
        try container.encode(write, forKey: .write)
        try container.encode(soundsLike, forKey: .soundsLike)
        // Written as an explicit null rather than omitted, as `HistoryEntry` does.
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(enabled, forKey: .enabled)
    }
}
