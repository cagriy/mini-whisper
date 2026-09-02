import Foundation
import MWConfig
import MWHotkeys
import MWStreaming
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct SettingsModelTests {
    private final class FakeSecrets: SecretStore, @unchecked Sendable {
        var stored: [KeyAccount: String] = [:]

        func secret(for account: KeyAccount) throws -> String? { stored[account] }
        func setSecret(_ secret: String, for account: KeyAccount) throws { stored[account] = secret }
        func removeSecret(for account: KeyAccount) throws { stored[account] = nil }
    }

    private final class FakeHotkeys: HotkeyCapturing, @unchecked Sendable {
        var begun = 0
        var cancelled = 0
        var updates: [BindingName: HotkeyCombo] = [:]

        func beginCapture() { begun += 1 }
        func cancelCapture() { cancelled += 1 }
        func update(binding: BindingName, combo: HotkeyCombo) { updates[binding] = combo }
    }

    private struct NoApps: AppListing {
        func runningApps() -> [AppChoice] { [] }
        func displayName(forBundleID bundleID: String) -> String? { nil }
    }

    private final class FakeSounds: SoundPreviewing, @unchecked Sendable {
        var volume: Float = -1
        var onPlays = 0

        func setVolume(_ volume: Float) { self.volume = volume }
        func playOn() { onPlays += 1 }
    }

    private struct Harness {
        let directory: URL
        let store: ConfigStore
        let secrets = FakeSecrets()
        let hotkeys = FakeHotkeys()
        let sounds = FakeSounds()

        init() {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mw-settings-\(UUID().uuidString)", isDirectory: true)
            store = ConfigStore(directory: directory)
        }

        @MainActor
        func model(osMajor: Int = 14, speechModel: AssetStatus = .unavailable) async -> SettingsModel {
            let model = SettingsModel(
                config: await store.load(),
                deps: SettingsModel.Dependencies(
                    store: store,
                    secrets: secrets,
                    hotkeys: hotkeys,
                    sounds: sounds,
                    platform: PlatformInfo(osMajor: osMajor, locale: Locale(identifier: "en_US")),
                    assetStatus: { speechModel },
                    installAssets: {},
                    prompts: PromptFiles(
                        directory: directory,
                        bundledCleanup: directory.appendingPathComponent("default_prompt.txt"),
                        bundledTranscribe: directory.appendingPathComponent("default_transcribe_prompt.txt")
                    ),
                    apps: NoApps(),
                    pruneHistory: { _ in },
                    clearHistory: {},
                    openHistory: {}
                )
            )
            await model.refreshSpeechModel()
            return model
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }

        /// A config.json as it exists on disk today: written by the Python app, so
        /// without the `streaming_engine` key (design §5.1, F32).
        func writeConfig(_ json: String) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: directory.appendingPathComponent("config.json"))
        }
    }

    @Test func cloudEngineRowsDisabledWithoutKeyWithReason() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        let reasons = [
            EngineName.openai: "Add an OpenAI key under Keys to enable",
            .elevenlabs: "Add an ElevenLabs key under Keys to enable",
            .speechmatics: "Add a Speechmatics key under Keys to enable",
        ]
        for (name, reason) in reasons {
            let row = try #require(model.engineRows.first { $0.name == name })
            #expect(!row.isEnabled)
            #expect(row.disabledReason == reason)
        }
        #expect(model.engineRows.first { $0.name == .onDevice }?.isEnabled == true)

        harness.secrets.stored[.elevenlabs] = "xi-key"
        model.refreshKeys()
        let elevenlabs = try #require(model.engineRows.first { $0.name == .elevenlabs })
        #expect(elevenlabs.isEnabled)
        #expect(elevenlabs.disabledReason == nil)
    }

    @Test func engineListMarksThePlatformDefaultWhenConfigNamesNoEngine() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try harness.writeConfig(#"{"streaming_enabled": true}"#)

        let old = await harness.model(osMajor: 14, speechModel: .notInstalled)
        #expect(old.config.streamingEngine == nil)
        #expect(old.selectedEngine == .onDevice)

        let pending = await harness.model(osMajor: 26, speechModel: .notInstalled)
        #expect(pending.selectedEngine == .onDevice)

        let installed = await harness.model(osMajor: 26, speechModel: .installed)
        #expect(installed.selectedEngine == .speechAnalyzer)

        await installed.selectEngine(.onDevice)
        #expect(installed.config.streamingEngine == .onDevice)
        #expect(installed.selectedEngine == .onDevice)
    }

    @Test func speechAnalyzerRowOnlyOn26() async {
        let harness = Harness()
        defer { harness.cleanUp() }

        let old = await harness.model(osMajor: 14, speechModel: .notInstalled)
        #expect(!old.engineRows.contains { $0.name == .speechAnalyzer })

        let new = await harness.model(osMajor: 26, speechModel: .notInstalled)
        #expect(new.engineRows.first?.name == .speechAnalyzer)
    }

    @Test func speechAnalyzerRowStates() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }

        for (status, expected) in [
            (AssetStatus.notInstalled, "Download model…"),
            (.installing(fractionCompleted: 0.45), "Downloading… 45%"),
            (.installed, "Installed"),
        ] {
            let model = await harness.model(osMajor: 26, speechModel: status)
            let row = try #require(model.engineRows.first { $0.name == .speechAnalyzer })
            #expect(row.accessory?.text == expected)
            #expect(row.subtitle == "On-device · macOS 26 · best accuracy")
        }

        // Unsupported locale or transcriber: selecting it would silently downgrade (F23).
        let unavailable = await harness.model(osMajor: 26, speechModel: .unavailable)
        #expect(!unavailable.engineRows.contains { $0.name == .speechAnalyzer })
    }

    @Test func cleanupToggleDisabledAndShownOffWithoutKeyButStoredValuePreserved() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        #expect(model.config.cleanupEnabled)
        #expect(!model.cleanupToggleEnabled)
        #expect(!model.cleanupShownOn)

        // A disabled control writes nothing, so the stored value survives (F26).
        #expect(await harness.store.load().cleanupEnabled)

        harness.secrets.stored[.openai] = "sk-abcdefgh1234"
        model.refreshKeys()
        #expect(model.cleanupToggleEnabled)
        #expect(model.cleanupShownOn)

        await model.setCleanupEnabled(false)
        #expect(!model.cleanupShownOn)
        #expect(await harness.store.load().cleanupEnabled == false)
    }

    @Test func openAIKeyMaskedAsSkPrefixAndLast4() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.secrets.stored[.openai] = "sk-abcdefgh1234"
        let model = await harness.model()

        #expect(model.mask(for: .openai) == "sk-…1234")
        #expect(model.mask(for: .elevenlabs).isEmpty)
    }

    @Test func otherKeysMaskedAsDots() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.secrets.stored[.elevenlabs] = "xi-secret-value"
        harness.secrets.stored[.speechmatics] = "sm-secret-value"
        let model = await harness.model()

        #expect(model.mask(for: .elevenlabs) == "••••••••••••")
        #expect(model.mask(for: .speechmatics) == "••••••••••••")
        // The mask must never leak any part of the stored key.
        #expect(!model.mask(for: .elevenlabs).contains("secret"))
    }

    @Test func saveKeyValidationMessages() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        model.saveKey(.openai, value: "   ")
        #expect(model.error(for: .openai) == "Enter a new API key to save.")
        #expect(harness.secrets.stored[.openai] == nil)

        model.saveKey(.openai, value: "abc123")
        #expect(model.error(for: .openai) == "Invalid key — must start with 'sk-'.")
        #expect(harness.secrets.stored[.openai] == nil)

        model.saveKey(.openai, value: " sk-abcdefgh1234 ")
        #expect(model.error(for: .openai) == nil)
        #expect(harness.secrets.stored[.openai] == "sk-abcdefgh1234")
        #expect(model.mask(for: .openai) == "sk-…1234")

        // Saving the mask back is "no new key", never a key called "sk-…1234".
        model.saveKey(.openai, value: "sk-…1234")
        #expect(model.error(for: .openai) == "Enter a new API key to save.")
        #expect(harness.secrets.stored[.openai] == "sk-abcdefgh1234")

        model.saveKey(.elevenlabs, value: "")
        #expect(model.error(for: .elevenlabs) == "Enter a new API key to save.")

        model.saveKey(.elevenlabs, value: "xi-key")
        #expect(model.error(for: .elevenlabs) == nil)
        #expect(harness.secrets.stored[.elevenlabs] == "xi-key")

        model.saveKey(.elevenlabs, value: "••••••••••••")
        #expect(model.error(for: .elevenlabs) == "Enter a new API key to save.")
        #expect(harness.secrets.stored[.elevenlabs] == "xi-key")
    }

    @Test func hotkeyCaptureAppliesAndSavesOnMainActor() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        model.beginCapture(.paste)
        #expect(harness.hotkeys.begun == 1)
        #expect(model.capturing == .paste)
        #expect(model.display(.paste) == "Press shortcut...")

        let combo = try HotkeyCombo.parse("shift+cmd+space")
        await model.handle(.captured(combo))

        #expect(model.capturing == nil)
        #expect(model.display(.paste) == combo.displayString)
        #expect(harness.hotkeys.updates[.paste] == combo)
        #expect(await harness.store.load().hotkey == "cmd+shift+space")

        model.beginCapture(.pasteSubmit)
        let submit = try HotkeyCombo.parse("alt_r")
        await model.handle(.captured(submit))
        #expect(await harness.store.load().submitHotkey == "alt_r")
        #expect(model.display(.pasteSubmit) == "Right ⌥")
    }

    @Test func hotkeyCaptureRejectsBareKeyAndReenters() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        model.beginCapture(.paste)
        await model.handle(.captureRejected)

        #expect(model.capturing == .paste)
        #expect(model.display(.paste) == "Press shortcut...")
        #expect(harness.hotkeys.updates.isEmpty)
        #expect(await harness.store.load().hotkey == "shift+cmd_r")
    }

    @Test func hotkeyCaptureEscRestoresPreviousDisplay() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        let previous = model.display(.paste)
        #expect(previous == "⇧Right ⌘")

        model.beginCapture(.paste)
        model.cancelCapture()

        #expect(harness.hotkeys.cancelled == 1)
        #expect(model.capturing == nil)
        #expect(model.display(.paste) == previous)
    }

    @Test func idleStopStepperRange10sTo10min() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        #expect(SettingsModel.idleStopSecondsRange == 10...600)

        await model.setIdleStopSeconds(5)
        #expect(model.config.idleStopSeconds == 10)

        await model.setIdleStopSeconds(9_999)
        #expect(model.config.idleStopSeconds == 600)
        #expect(await harness.store.load().idleStopSeconds == 600)

        await model.setIdleStopSeconds(90)
        #expect(model.idleStopLabel == "90 s")
    }

    @Test func toggleCapStepperRange1To30min() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        #expect(SettingsModel.toggleCapMinutesRange == 1...30)

        await model.setToggleCapMinutes(0)
        #expect(model.config.toggleMaxSeconds == 60)

        await model.setToggleCapMinutes(99)
        #expect(model.config.toggleMaxSeconds == 1_800)
        #expect(await harness.store.load().toggleMaxSeconds == 1_800)
        #expect(model.toggleCapLabel == "30 min")
    }

    @Test func volumeSliderPreviewsOnOnRelease() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        model.volume = 0.4237
        #expect(harness.sounds.onPlays == 0)

        await model.commitVolume()
        #expect(model.config.soundVolume == 0.42)
        #expect(await harness.store.load().soundVolume == 0.42)
        #expect(harness.sounds.volume == 0.42)
        #expect(harness.sounds.onPlays == 1)
    }
}
