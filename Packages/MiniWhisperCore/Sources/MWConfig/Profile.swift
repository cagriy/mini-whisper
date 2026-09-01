import Foundation

/// A per-app cleanup profile (F27). `cleanupPrompt == nil` means "use prompt.txt".
public struct Profile: Equatable, Sendable {
    public var id: String
    public var name: String
    public var bundleIDs: [String]
    public var cleanupEnabled: Bool
    public var submitKey: SubmitKey
    public var cleanupPrompt: String?

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        bundleIDs: [String] = [],
        cleanupEnabled: Bool = true,
        submitKey: SubmitKey = .enter,
        cleanupPrompt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.cleanupEnabled = cleanupEnabled
        self.submitKey = submitKey
        self.cleanupPrompt = cleanupPrompt
    }
}

extension Profile: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bundleIDs = "bundle_ids"
        case cleanupEnabled = "cleanup_enabled"
        case submitKey = "submit_key"
        case cleanupPrompt = "cleanup_prompt"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        bundleIDs = try container.decodeIfPresent([String].self, forKey: .bundleIDs) ?? []
        cleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? true
        // An unrecognised submit_key falls back to Enter rather than failing the whole load.
        submitKey = try container.decodeIfPresent(String.self, forKey: .submitKey)
            .flatMap(SubmitKey.init(rawValue:)) ?? .enter
        cleanupPrompt = try container.decodeIfPresent(String.self, forKey: .cleanupPrompt)
    }
}
