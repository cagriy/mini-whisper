import Foundation
import MWConfig
import MWHotkeys
import MWMeetings
import MWOverlaySim
import MWStreaming
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct SettingsModelTests {
    /// The Meetings pane's reach into the store, the installer and the pasteboard.
    private final class MeetingHooks: @unchecked Sendable {
        var entries: [IndexEntry] = []
        var installed = false
        var installResult: Result<Void, CommandLineToolInstaller.Failure> = .success(())
        var copied: [String] = []
        var foldersShown = 0
    }

    private struct Harness {
        let directory: URL
        let store: ConfigStore
        let secrets = FakeSecrets()
        let hotkeys = FakeHotkeys()
        let sounds = FakeSounds()
        let updates = FakeUpdater()
        let meetings = MeetingHooks()

        init() {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mw-settings-\(UUID().uuidString)", isDirectory: true)
            store = ConfigStore(directory: directory)
        }

        @MainActor
        func model(
            osMajor: Int = 14,
            speechModel: AssetStatus = .unavailable,
            status: (@Sendable () async -> AssetStatus)? = nil,
            installAssets: @escaping @Sendable () async throws -> Void = {}
        ) async -> SettingsModel {
            let model = SettingsModel(
                config: await store.load(),
                deps: SettingsModel.Dependencies(
                    store: store,
                    secrets: secrets,
                    hotkeys: hotkeys,
                    sounds: sounds,
                    updates: updates,
                    platform: PlatformInfo(osMajor: osMajor, locale: Locale(identifier: "en_US")),
                    assetStatus: status ?? { speechModel },
                    installAssets: installAssets,
                    prompts: PromptFiles(
                        directory: directory,
                        bundledCleanup: directory.appendingPathComponent("default_prompt.txt"),
                        bundledTranscribe: directory.appendingPathComponent("default_transcribe_prompt.txt"),
                        bundledSummary: directory.appendingPathComponent("default_summary_prompt.txt")
                    ),
                    apps: StubApps(),
                    pruneHistory: { _ in },
                    clearHistory: {},
                    openCorrection: { _ in },
                    accountName: "Alex Morgan",
                    meetingIndex: { [meetings] in meetings.entries },
                    showMeetingsFolder: { [meetings] in meetings.foldersShown += 1 },
                    installTool: { [meetings] in
                        if case .success = meetings.installResult { meetings.installed = true }
                        return meetings.installResult
                    },
                    isToolInstalled: { [meetings] in meetings.installed },
                    toolBinaryPath: "/Applications/Mini Whisper.app/Contents/MacOS/Mini Whisper",
                    copy: { [meetings] in meetings.copied.append($0) }
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

    @Test func assemblyAIEngineIsGatedOnItsKey() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        let locked = try #require(model.engineRows.first { $0.name == .assemblyai })
        #expect(locked.title == "AssemblyAI")
        #expect(!locked.isEnabled)
        #expect(locked.disabledReason == "Add an AssemblyAI key under Keys to enable")
        await model.selectEngine(.assemblyai)
        #expect(model.config.streamingEngine != .assemblyai)

        harness.secrets.stored[.assemblyai] = "aai-key"
        model.refreshKeys()
        let unlocked = try #require(model.engineRows.first { $0.name == .assemblyai })
        #expect(unlocked.isEnabled)
        #expect(unlocked.disabledReason == nil)
        await model.selectEngine(.assemblyai)
        #expect(model.config.streamingEngine == .assemblyai)
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

    /// One-shot cross-task signal; a send before the wait is still delivered.
    private final class Signal: @unchecked Sendable {
        private let stream: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation

        init() { (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded) }

        func send() { continuation.yield(()) }

        func wait() async {
            var iterator = stream.makeAsyncIterator()
            _ = await iterator.next()
        }
    }

    private final class StatusBox: @unchecked Sendable {
        private let lock = NSLock()
        private var status: AssetStatus

        init(_ status: AssetStatus) { self.status = status }

        var value: AssetStatus {
            get { lock.withLock { status } }
            set { lock.withLock { status = newValue } }
        }
    }

    /// Pressing Download used to leave the row saying "Download model…" for the whole
    /// download, which reads as a dead button.
    @Test func downloadReportsProgressUntilTheModelIsInstalled() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let started = Signal()
        let release = Signal()
        let status = StatusBox(.notInstalled)
        let model = await harness.model(
            osMajor: 26,
            status: { status.value },
            installAssets: {
                started.send()
                await release.wait()
                status.value = .installed
            }
        )
        #expect(model.engineRows.first?.accessory == .download)

        let install = Task { await model.installSpeechModel() }
        await started.wait()
        #expect(model.engineRows.first?.accessory == .installing(fraction: 0))

        release.send()
        await install.value
        #expect(model.engineRows.first?.accessory == .installed)
    }

    @Test func downloadingWithoutProgressOmitsThePercentage() {
        #expect(SettingsModel.EngineAccessory.installing(fraction: 0).text == "Downloading…")
        #expect(SettingsModel.EngineAccessory.installing(fraction: 0.45).text == "Downloading… 45%")
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

    @Test func anthropicKeyMustStartWithSkAnt() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        model.saveKey(.anthropic, value: "sk-abc")
        #expect(model.error(for: .anthropic) == "Invalid key — must start with 'sk-ant-'.")
        #expect(harness.secrets.stored[.anthropic] == nil)

        model.saveKey(.anthropic, value: "sk-ant-abc")
        #expect(model.error(for: .anthropic) == nil)
        #expect(harness.secrets.stored[.anthropic] == "sk-ant-abc")
        #expect(model.mask(for: .anthropic) == "••••••••••••")
    }

    @Test func assemblyAIKeyAcceptsAnyNonEmptyValue() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        model.saveKey(.assemblyai, value: "")
        #expect(model.error(for: .assemblyai) == "Enter a new API key to save.")

        model.saveKey(.assemblyai, value: "placeholder-not-a-real-key")
        #expect(model.error(for: .assemblyai) == nil)
        #expect(harness.secrets.stored[.assemblyai] == "placeholder-not-a-real-key")
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

    @Test func leavingTheHotkeysSectionCancelsCapture() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        let previous = model.display(.paste)
        model.selection = .hotkeys

        model.beginCapture(.paste)
        model.selection = .keys

        #expect(harness.hotkeys.cancelled == 1)
        #expect(model.capturing == nil)
        #expect(model.display(.paste) == previous)
    }

    @Test func changingSectionWhileNotCapturingCancelsNothing() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        model.selection = .hotkeys
        model.selection = .keys
        model.selection = .hotkeys
        model.selection = .general

        #expect(harness.hotkeys.cancelled == 0)
        #expect(model.capturing == nil)
    }

    @Test func capturingMeetingStoresMeetingHotkey() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        #expect(model.display(.meeting) == "⌥⌘⌃M")

        model.beginCapture(.meeting)
        let combo = try HotkeyCombo.parse("ctrl+alt+cmd+j")
        await model.handle(.captured(combo))

        #expect(model.capturing == nil)
        #expect(model.display(.meeting) == "⌥⌘⌃J")
        #expect(harness.hotkeys.updates[.meeting] == combo)
        #expect(await harness.store.load().meetingHotkey == "alt+cmd+ctrl+j")
    }

    @Test func captureEqualToAnotherBindingIsRefused() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        model.beginCapture(.meeting)
        await model.handle(.captured(try HotkeyCombo.parse("shift+cmd_r")))

        #expect(model.hotkeyError(for: .meeting) == "Already used by Record")
        #expect(model.capturing == nil)
        #expect(model.display(.meeting) == "⌥⌘⌃M")
        #expect(harness.hotkeys.updates.isEmpty)
        #expect(await harness.store.load() == Config())

        model.beginCapture(.meeting)
        #expect(model.hotkeyError(for: .meeting) == nil)
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

    /// R36: the correction window's save reaches the open panes through AppDelegate's
    /// config-change consumer, which is still the only one (N4).
    @Test func refreshAdoptsAConfigWrittenElsewhere() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        #expect(model.vocabulary.terms.isEmpty)
        #expect(model.corrections.rows.isEmpty)

        try await harness.store.update { @Sendable in
            $0.vocabulary = ["xcodegen"]
            $0.corrections = [CorrectionRule(id: "r1", heard: "get hub", write: "GitHub")]
        }
        model.refresh(from: await harness.store.load())

        #expect(model.config.vocabulary == ["xcodegen"])
        #expect(model.vocabulary.terms == ["xcodegen"])
        #expect(model.corrections.rows.map(\.write) == ["GitHub"])
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

    /// Sparkle owns this preference, so the toggle reads and writes it through the
    /// updater rather than `config.json`.
    @Test func automaticUpdatesReadAndWriteThroughTheUpdater() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.updates.automaticallyChecksForUpdates = true
        let model = await harness.model()

        #expect(model.automaticUpdatesEnabled)

        model.setAutomaticUpdates(false)
        #expect(!harness.updates.automaticallyChecksForUpdates)
        #expect(!model.automaticUpdatesEnabled)

        model.checkForUpdatesNow()
        #expect(harness.updates.checks == 1)
    }

    // MARK: - Overlay (design §5.4)

    @Test func overlaySectionSitsBetweenHistoryAndSound() {
        #expect(SettingsModel.Section.allCases == [
            .general, .hotkeys, .keys, .cleanup, .vocabulary, .history, .meetings, .overlay, .sound,
        ])
        #expect(SettingsModel.Section.overlay.title == "Overlay")
        #expect(SettingsModel.Section.overlay.symbolName == "sparkles.rectangle.stack")
    }

    @Test func historySectionIsTitledDictations() {
        #expect(SettingsModel.Section.history.title == "Dictations")
    }

    @Test func setOverlayStyleWritesTheConfigKey() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        #expect(model.selectedOverlayStyle == .softMeter)

        await model.setOverlayStyle(.petalIris)

        #expect(model.selectedOverlayStyle == .petalIris)
        #expect(await harness.store.load().overlayStyle == .petalIris)
    }

    /// R15: an edit made outside Settings reaches the pane through the one
    /// config-change consumer.
    @Test func refreshFromConfigUpdatesTheSelection() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        try await harness.store.update { @Sendable in $0.overlayStyle = .resonantHalo }
        model.refresh(from: await harness.store.load())

        #expect(model.selectedOverlayStyle == .resonantHalo)
    }

    @Test func overlayStyleRowsMatchTheCatalog() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        #expect(model.overlayStyleRows == OverlayStyleCatalog.rows)
        #expect(model.overlayStyleRows.count == OverlayStyle.allCases.count)
    }

    // MARK: - Meetings (design §3 R4, R20, R22)

    @Test func meetingsSectionTitleAndSymbol() {
        #expect(SettingsModel.Section.meetings.title == "Meetings")
        #expect(SettingsModel.Section.meetings.symbolName == "person.2.wave.2")
    }

    @Test func engineRowsShowPricesAndKeyGating() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.secrets.stored[.assemblyai] = "placeholder-not-a-real-key"
        let model = await harness.model()

        #expect(model.meetingEngineRows.map(\.engine) == MeetingEngine.allCases)
        #expect(model.meetingEngineRows.map(\.title) == MeetingEngine.allCases.map(\.title))
        #expect(model.meetingEngineRows.map(\.price) == ["$0.45/h", "$0.80/h", "$0.15 + $0.12/h", "$0.45 + $0.12/h"])

        let standard = try #require(model.meetingEngineRows.first)
        #expect(!standard.isEnabled)
        #expect(standard.disabledReason == "Add a Speechmatics key under Keys to enable")
        let streaming = try #require(model.meetingEngineRows.first { $0.engine == .assemblyaiStreaming })
        #expect(streaming.isEnabled)
        #expect(streaming.disabledReason == nil)

        harness.secrets.stored[.speechmatics] = "placeholder-not-a-real-key"
        model.refreshKeys()
        #expect(model.meetingEngineRows.map(\.isEnabled) == [true, true, true, true])
    }

    @Test func enginePricesFollowPricingOverrides() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try harness.writeConfig(#"{"pricing_overrides": {"speechmatics": 0.01, "assemblyai_diarization": 0.001}}"#)
        let model = await harness.model()

        #expect(model.meetingEngineRows.map(\.price) == ["$0.60/h", "$0.80/h", "$0.15 + $0.06/h", "$0.45 + $0.06/h"])
    }

    @Test func selectingAnEngineWritesMeetingEngine() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.secrets.stored[.speechmatics] = "placeholder-not-a-real-key"
        let model = await harness.model()
        #expect(model.activeMeetingEngine == .speechmaticsStandard)

        await model.selectMeetingEngine(.speechmaticsEnhanced)
        #expect(model.activeMeetingEngine == .speechmaticsEnhanced)
        #expect(await harness.store.load().meetingEngine == .speechmaticsEnhanced)

        // A row without its key cannot be chosen.
        await model.selectMeetingEngine(.assemblyaiPro)
        #expect(await harness.store.load().meetingEngine == .speechmaticsEnhanced)
    }

    /// Design §5.7: a stored tier whose key was removed stays in config.json, shown disabled,
    /// while meetings run on the first tier that has a key.
    @Test func storedEngineWithoutAKeyShowsDisabledAndTheFirstKeyedTierIsActive() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try harness.writeConfig(#"{"meeting_engine": "assemblyai_pro"}"#)
        harness.secrets.stored[.speechmatics] = "placeholder-not-a-real-key"
        let model = await harness.model()

        let stored = try #require(model.meetingEngineRows.first { $0.engine == .assemblyaiPro })
        #expect(!stored.isEnabled)
        #expect(stored.disabledReason == "Add an AssemblyAI key under Keys to enable")
        #expect(model.activeMeetingEngine == .speechmaticsStandard)
        #expect(await harness.store.load().meetingEngine == .assemblyaiPro)

        let keyless = await Harness().model()
        #expect(keyless.activeMeetingEngine == nil)
    }

    @Test func userNameDefaultsToTheFullName() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        #expect(model.meetingUserName == "Alex Morgan")

        await model.setMeetingUserName(" Alex ")
        #expect(model.meetingUserName == "Alex")
        #expect(await harness.store.load().meetingUserName == "Alex")

        // Clearing the field brings the account name back rather than storing a blank name.
        await model.setMeetingUserName("  ")
        #expect(model.meetingUserName == "Alex Morgan")
        #expect(await harness.store.load().meetingUserName == nil)
    }

    @Test func keepAudioToggleWritesConfig() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        #expect(model.config.meetingKeepAudio)

        await model.setMeetingKeepAudio(false)
        #expect(!model.config.meetingKeepAudio)
        #expect(await harness.store.load().meetingKeepAudio == false)
    }

    @Test func privacySettingsURLIsTheAudioCaptureAnchor() {
        #expect(SettingsModel.privacySettingsURL.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
    }

    @Test func summaryPromptSavesAndRestoresTheDefault() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try FileManager.default.createDirectory(at: harness.directory, withIntermediateDirectories: true)
        try Data("Summarise the meeting.\n".utf8)
            .write(to: harness.directory.appendingPathComponent("default_summary_prompt.txt"))
        let model = await harness.model()
        let file = harness.directory.appendingPathComponent("summary_prompt.txt")

        model.loadSummaryPrompt()
        #expect(model.summaryPromptDraft == "Summarise the meeting.")
        #expect(model.summaryPromptURL == file)

        model.summaryPromptDraft = "Only list action items."
        model.saveSummaryPrompt()
        #expect(try String(contentsOf: file, encoding: .utf8) == "Only list action items.")

        model.restoreDefaultSummaryPrompt()
        #expect(model.summaryPromptDraft == "Summarise the meeting.")
        #expect(try String(contentsOf: file, encoding: .utf8) == "Summarise the meeting.\n")
        #expect(model.promptError == nil)
    }

    @Test func summaryNoteAsksForAnAnthropicKeyUntilOneIsStored() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        #expect(model.summaryKeyHint == "Add an Anthropic key under Keys to enable.")

        harness.secrets.stored[.anthropic] = "sk-ant-placeholder"
        model.refreshKeys()
        #expect(model.summaryKeyHint == nil)
    }

    @Test func storageRowCountsMeetingsAndAudio() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        await model.refreshMeetings()
        #expect(model.storageText == "0 meetings")

        harness.meetings.entries = [Self.entry(audioBytes: 0)]
        await model.refreshMeetings()
        #expect(model.storageText == "1 meeting")

        harness.meetings.entries = [
            Self.entry(audioBytes: 300_000_000), Self.entry(audioBytes: 10_400_000), Self.entry(audioBytes: 0),
        ]
        await model.refreshMeetings()
        #expect(model.storageText == "3 meetings · 310 MB audio")

        model.showMeetingsFolder()
        #expect(harness.meetings.foldersShown == 1)
    }

    @Test func installReportsSuccessOrTheErrorText() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        await model.refreshMeetings()
        #expect(model.toolStatus == "Not installed")

        harness.meetings.installResult = .failure(CommandLineToolInstaller.Failure(message: "User canceled."))
        model.installTool()
        #expect(model.toolStatus == "User canceled.")
        // Coming back to the pane shows the state on disk, not the last attempt's reason.
        await model.refreshMeetings()
        #expect(model.toolStatus == "Not installed")

        harness.meetings.installResult = .success(())
        model.installTool()
        #expect(model.toolStatus == "Installed")
    }

    @Test func claudeCodeCommandFollowsInstallState() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        await model.refreshMeetings()
        #expect(model.claudeCodeCommand
            == "claude mcp add --transport stdio mini-whisper -- '/Applications/Mini Whisper.app/Contents/MacOS/Mini Whisper' mcp")

        harness.meetings.installed = true
        await model.refreshMeetings()
        #expect(model.claudeCodeCommand == "claude mcp add --transport stdio mini-whisper -- mini-whisper mcp")
    }

    @Test func copyPutsTheCommandOnThePasteboard() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.meetings.installed = true
        let model = await harness.model()
        await model.refreshMeetings()

        model.copyClaudeCodeCommand()
        #expect(harness.meetings.copied == ["claude mcp add --transport stdio mini-whisper -- mini-whisper mcp"])
    }

    @Test func chatGPTCommandFollowsInstallStateAndCopies() async {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        await model.refreshMeetings()
        #expect(model.chatGPTCommand == "/Applications/Mini Whisper.app/Contents/MacOS/Mini Whisper")

        harness.meetings.installed = true
        await model.refreshMeetings()
        model.copyChatGPTCommand()
        #expect(harness.meetings.copied == ["/usr/local/bin/mini-whisper"])
    }

    private static func entry(audioBytes: Int) -> IndexEntry {
        IndexEntry(
            id: UUID(), title: "Standup", startedAt: Date(timeIntervalSince1970: 1_794_236_400), endedAt: nil,
            duration: 600, mode: .inRoom, app: nil, engine: .speechmaticsStandard, speakerCount: 2, costUSD: 0.08,
            hasSummary: false, audioBytes: audioBytes, excerpt: ""
        )
    }
}
