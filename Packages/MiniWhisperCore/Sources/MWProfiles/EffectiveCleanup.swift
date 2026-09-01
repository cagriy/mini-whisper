import MWConfig

/// Cleanup runs only when the global setting, an OpenAI key and the resolved profile all
/// allow it (F26). The stored setting is never rewritten by this rule.
public enum EffectiveCleanup {
    public static func isOn(config: Config, hasOpenAIKey: Bool, profile: ResolvedProfile) -> Bool {
        config.cleanupEnabled && hasOpenAIKey && profile.cleanupEnabled
    }
}
