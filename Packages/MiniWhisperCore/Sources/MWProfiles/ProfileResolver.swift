import MWConfig

/// Picks the profile for the frontmost app: the first one listing its bundle ID, else the
/// implicit Default built from the top-level settings and `prompt.txt` (F27).
public struct ProfileResolver {
    private let config: Config
    private let defaultPrompt: () throws -> String

    public init(config: Config, defaultPrompt: @escaping () throws -> String) {
        self.config = config
        self.defaultPrompt = defaultPrompt
    }

    public func resolve(bundleID: String?) throws -> ResolvedProfile {
        guard let bundleID,
              let profile = config.profiles.first(where: { $0.bundleIDs.contains(bundleID) })
        else {
            return ResolvedProfile(
                name: Self.defaultName,
                cleanupEnabled: config.cleanupEnabled,
                submitKey: .enter,
                cleanupPrompt: try defaultPrompt(),
                isDefault: true
            )
        }
        return ResolvedProfile(
            name: profile.name,
            cleanupEnabled: profile.cleanupEnabled,
            submitKey: profile.submitKey,
            // A null `cleanup_prompt` means "use prompt.txt" (design §5.3).
            cleanupPrompt: try profile.cleanupPrompt ?? defaultPrompt(),
            isDefault: false
        )
    }

    private static let defaultName = "Default"
}
