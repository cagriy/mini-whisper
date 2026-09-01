import MWConfig
import Testing

import MWProfiles

/// Profile lookup for the frontmost app (F27): first profile listing the bundle ID wins,
/// everything else falls to the implicit Default.
@Suite struct ProfileResolverTests {
    private static let promptTxt = "Clean up the transcript."

    private func config(profiles: [Profile], cleanupEnabled: Bool = true) -> Config {
        var config = Config()
        config.cleanupEnabled = cleanupEnabled
        config.profiles = profiles
        return config
    }

    private func resolver(_ config: Config) -> ProfileResolver {
        ProfileResolver(config: config, defaultPrompt: { Self.promptTxt })
    }

    private let terminal = Profile(
        id: "1",
        name: "Terminal",
        bundleIDs: ["com.apple.Terminal", "com.googlecode.iterm2"],
        cleanupEnabled: false,
        submitKey: .enter,
        cleanupPrompt: "Keep shell commands verbatim."
    )

    @Test func firstProfileContainingBundleIDWins() throws {
        let shadowing = Profile(
            id: "2",
            name: "Shadowing",
            bundleIDs: ["com.apple.Terminal"],
            cleanupEnabled: true,
            submitKey: .cmdEnter,
            cleanupPrompt: "Never used."
        )
        let resolved = try resolver(config(profiles: [terminal, shadowing]))
            .resolve(bundleID: "com.apple.Terminal")

        #expect(resolved.name == "Terminal")
        #expect(resolved.cleanupEnabled == false)
        #expect(resolved.submitKey == .enter)
        #expect(resolved.cleanupPrompt == "Keep shell commands verbatim.")
        #expect(resolved.isDefault == false)
    }

    @Test func matchesAnyBundleIDInTheProfile() throws {
        let resolved = try resolver(config(profiles: [terminal]))
            .resolve(bundleID: "com.googlecode.iterm2")
        #expect(resolved.name == "Terminal")
    }

    @Test func noMatchYieldsImplicitDefault() throws {
        let resolved = try resolver(config(profiles: [terminal]))
            .resolve(bundleID: "com.tinyspeck.slackmacgap")

        #expect(resolved.isDefault)
        #expect(resolved.name == "Default")
        #expect(resolved.cleanupEnabled)
        #expect(resolved.submitKey == .enter)
        #expect(resolved.cleanupPrompt == Self.promptTxt)
    }

    @Test func defaultTakesCleanupFlagFromTopLevelConfig() throws {
        let resolved = try resolver(config(profiles: [], cleanupEnabled: false))
            .resolve(bundleID: "com.tinyspeck.slackmacgap")
        #expect(resolved.isDefault)
        #expect(resolved.cleanupEnabled == false)
    }

    @Test func nilBundleIDYieldsDefault() throws {
        let resolved = try resolver(config(profiles: [terminal])).resolve(bundleID: nil)
        #expect(resolved.isDefault)
        #expect(resolved.cleanupPrompt == Self.promptTxt)
    }

    @Test func profileNullPromptFallsBackToPromptTxt() throws {
        let slack = Profile(
            id: "3",
            name: "Slack",
            bundleIDs: ["com.tinyspeck.slackmacgap"],
            cleanupEnabled: true,
            submitKey: .shiftEnter,
            cleanupPrompt: nil
        )
        let resolved = try resolver(config(profiles: [slack]))
            .resolve(bundleID: "com.tinyspeck.slackmacgap")

        #expect(resolved.isDefault == false)
        #expect(resolved.name == "Slack")
        #expect(resolved.submitKey == .shiftEnter)
        #expect(resolved.cleanupPrompt == Self.promptTxt)
    }
}
