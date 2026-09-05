import Foundation
import MWConfig
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct ProfilesEditorModelTests {
    private static let promptText = "Clean the transcript."

    private struct Harness {
        let directory: URL
        let store: ConfigStore
        var apps = StubApps()

        init() {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mw-profiles-\(UUID().uuidString)", isDirectory: true)
            store = ConfigStore(directory: directory)
        }

        @MainActor
        func model() async -> ProfilesEditorModel {
            ProfilesEditorModel(
                config: await store.load(),
                store: store,
                apps: apps,
                defaultPrompt: { ProfilesEditorModelTests.promptText }
            )
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func addCreatesUUIDProfileWithEnterDefault() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        await model.add()
        let profile = try #require(model.profiles.first)
        #expect(model.profiles.count == 1)
        #expect(UUID(uuidString: profile.id) != nil)
        #expect(profile.submitKey == .enter)
        #expect(profile.cleanupEnabled)
        #expect(profile.bundleIDs.isEmpty)
        #expect(await harness.store.load().profiles.map(\.id) == [profile.id])
    }

    @Test func bundleIDAlreadyInAnotherProfileIsRejected() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        await model.add()
        await model.add()
        let first = try #require(model.profiles.first?.id)
        let second = try #require(model.profiles.last?.id)

        #expect(await model.addBundleID("com.apple.Terminal", to: first))
        #expect(model.profiles.first?.bundleIDs == ["com.apple.Terminal"])

        #expect(await model.addBundleID("com.apple.Terminal", to: second) == false)
        #expect(model.profiles.last?.bundleIDs.isEmpty == true)
        #expect(model.appAssignmentError != nil)

        let stored = await harness.store.load().profiles
        #expect(stored.flatMap(\.bundleIDs) == ["com.apple.Terminal"])
    }

    @Test func removeDeletesProfile() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        await model.add()
        await model.add()
        let doomed = try #require(model.profiles.first?.id)

        await model.remove(doomed)
        #expect(model.profiles.count == 1)
        #expect(!model.profiles.contains { $0.id == doomed })
        #expect(await harness.store.load().profiles.count == 1)
    }

    @Test func defaultRowIsSyntheticAndUsesPromptTxt() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        let row = try #require(model.rows.first)
        #expect(row.id == ProfilesEditorModel.defaultRowID)
        #expect(row.isDefault)
        #expect(row.name == "Default")
        #expect(row.apps == "everything else")
        #expect(row.cleanup == "on")
        #expect(row.submitKey == "Enter")
        #expect(model.profiles.isEmpty)
        #expect(model.prompt(for: ProfilesEditorModel.defaultRowID) == Self.promptText)

        await model.add()
        #expect(model.rows.count == 2)
        #expect(model.rows.first?.isDefault == true)
    }

    @Test func nullPromptMeansPromptTxt() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        await model.add()
        let id = try #require(model.profiles.first?.id)
        #expect(model.profiles.first?.cleanupPrompt == nil)
        #expect(model.prompt(for: id) == Self.promptText)

        await model.setPrompt("Keep shell commands verbatim.", for: id)
        #expect(model.prompt(for: id) == "Keep shell commands verbatim.")
        #expect(await harness.store.load().profiles.first?.cleanupPrompt == "Keep shell commands verbatim.")

        // Emptying the editor means "use prompt.txt" again (design §5.3).
        await model.setPrompt("   ", for: id)
        #expect(model.profiles.first?.cleanupPrompt == nil)
        #expect(model.prompt(for: id) == Self.promptText)
    }

    @Test func runningAppsListedByBundleID() async {
        var harness = Harness()
        defer { harness.cleanUp() }
        harness.apps = StubApps(apps: [
            AppChoice(bundleID: "com.b", name: "Beta"),
            AppChoice(bundleID: "com.a", name: "Alpha"),
            AppChoice(bundleID: "com.a", name: "Alpha"),
        ])
        let model = await harness.model()

        #expect(model.runningApps.map(\.bundleID) == ["com.a", "com.b"])
        #expect(model.runningApps.map(\.name) == ["Alpha", "Beta"])
    }
}
