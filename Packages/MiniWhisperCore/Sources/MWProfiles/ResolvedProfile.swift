import MWConfig

public struct ResolvedProfile: Equatable, Sendable {
    public var name: String
    public var cleanupEnabled: Bool
    public var submitKey: SubmitKey
    public var cleanupPrompt: String
    public var isDefault: Bool

    public init(
        name: String,
        cleanupEnabled: Bool,
        submitKey: SubmitKey,
        cleanupPrompt: String,
        isDefault: Bool
    ) {
        self.name = name
        self.cleanupEnabled = cleanupEnabled
        self.submitKey = submitKey
        self.cleanupPrompt = cleanupPrompt
        self.isDefault = isDefault
    }
}
