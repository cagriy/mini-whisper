import AppKit
import MWAudio
import MWConfig
import MWCorrections
import MWHistory
import MWHotkeys
import MWMeetingPipeline
import MWMeetings
import MWOverlaySim
import MWPaste
import MWPipeline
import MWStreaming
import MWSupport
import MWUsage
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let configDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/mini-whisper", isDirectory: true)

    private let sounds = SoundPlayer()
    private let retentionDays = OSAllocatedUnfairLock(initialState: 7)

    private var statusItem: StatusItemController?
    private var router: UIEventRouter?
    private var controller: DictationController?
    private var listener: GlobalKeyListener?
    private var audio: AudioCaptureEngine?
    private var configTask: Task<Void, Never>?
    private var onboarding: OnboardingWindowController?
    private var settings: SettingsWindowController?
    private var settingsDependencies: SettingsModel.Dependencies?
    private var historyWindow: HistoryWindowController?
    private var historyDependencies: HistoryListModel.Dependencies?
    private var correctionWindow: CorrectionWindowController?
    private var correctionDependencies: CorrectionModel.Dependencies?
    private var appliedBindings: [BindingName: HotkeyCombo] = [:]
    private var meetings: MeetingCoordinator?
    /// The config as last loaded or changed, for the meeting chooser.
    private var config = Config()
    private var overlay: OverlayPanelController?
    private var appliedOverlayStyle: OverlayStyle?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The AppTests bundle is hosted by this app; starting normally there would
        // touch the user's config, Keychain and input devices.
        guard !LaunchArguments.isRunningTests else { return }

        guard SingleInstanceGuard.claim() else { exit(0) }
        configureLogging()
        AppUpdater.start()

        let permitted = PermissionMonitor.allGranted
        statusItem = StatusItemController(
            sounds: sounds,
            onCorrectLast: { [weak self] in self?.correctLast() },
            onStartMeeting: { [weak self] in self?.meetings?.openChooser() },
            onStopMeeting: { [weak self] in Task { await self?.meetings?.stop() } },
            onShowMeeting: { [weak self] in self?.meetings?.show() },
            onHistory: { [weak self] in self?.openHistory() },
            onSettings: { [weak self] in self?.openSettings() },
            onQuit: { [weak self] in self?.quit() }
        )

        if permitted {
            Task { await startNormal() }
        } else {
            Log.ui.info(
                "Permissions missing (microphone \(PermissionMonitor.microphoneGranted),"
                    + " accessibility \(PermissionMonitor.accessibilityGranted)); onboarding"
            )
            showOnboarding()
        }
    }

    /// F33: the wizard owns the launch until every permission is granted, then
    /// Continue starts normal operation in this process.
    private func showOnboarding() {
        let onboarding = OnboardingWindowController { [weak self] in
            self?.onboarding = nil
            Task { await self?.startNormal() }
        }
        self.onboarding = onboarding
        onboarding.show()
    }

    // MARK: - Composition root

    private func startNormal() async {
        let configStore = ConfigStore(directory: Self.configDirectory)
        let config = await configStore.load()
        apply(config)

        let secrets = KeychainStore()
        let analyzer = SpeechAnalyzerBridge()
        let prompts = PromptFiles(
            directory: Self.configDirectory,
            bundledCleanup: Self.bundledPrompt("default_prompt"),
            bundledTranscribe: Self.bundledPrompt("default_transcribe_prompt"),
            bundledSummary: Self.bundledPrompt("default_summary_prompt")
        )
        let history = HistoryStore(
            url: Self.configDirectory.appendingPathComponent("history.jsonl"),
            retention: { [retentionDays] in retentionDays.withLock { $0 } }
        )
        let audio = AudioCaptureEngine(backend: AVAudioEngineBackend())
        self.audio = audio
        let usage = UsageStore(config: configStore)
        let openAI = KeyedOpenAIClient(secrets: secrets)
        let processes = RunningProcessCheck()
        let paster = Paster(
            pasteboard: NSPasteboardAccess(),
            poster: CGEventKeyPoster(),
            accessibility: AXTrustCheck(),
            process: processes,
            clock: SystemClock()
        )
        let deps = Dependencies(
            audio: audio,
            engines: EngineFactory(),
            frontmost: NSWorkspaceFrontmostApp(),
            transcriber: openAI,
            cleaner: openAI,
            paster: paster,
            secrets: secrets,
            usage: usage,
            history: history,
            sounds: sounds,
            prompts: prompts
        )

        let controller = DictationController(deps: deps, config: configStore)
        self.controller = controller
        meetings = makeMeetings(
            audio: audio, secrets: secrets, configStore: configStore, usage: usage, prompts: prompts
        )

        if let statusItem {
            // §5.5: the panels exist off-screen before the first press.
            let overlay = OverlayPanelController(
                style: config.overlayStyle,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
            self.overlay = overlay
            let caption = CaptionPanelController()
            let router = UIEventRouter(
                statusItem: statusItem,
                overlay: overlay,
                caption: caption,
                placement: DisplayPlacement(
                    focused: AXFocusedWindow(),
                    pointer: NSEventPointer(),
                    screens: NSScreenList()
                ),
                frontmost: NSWorkspaceFrontmostApp()
            )
            router.start(controller.uiEvents)
            self.router = router

            let totals = await usage.totals()
            statusItem.setUsage(today: totals.today, monthCost: totals.monthCost)
        }

        let listener = GlobalKeyListener(
            bindings: Self.bindings(from: config),
            onAction: { [weak self, weak controller] action in
                switch HotkeyRouting.route(action, meetingActive: self?.meetings?.isActive ?? false) {
                case .dictation(.pressed(let name)): controller?.hotkeyPressed(name)
                case .dictation(.released(let name)): controller?.hotkeyReleased(name)
                case .meeting: Task { await self?.meetings?.toggle() }
                case .notice(let message): self?.router?.show(error: message)
                case .settings(let action):
                    // Capture belongs to the Settings hotkey fields (F7).
                    guard let model = self?.settings?.model else { return }
                    Task { await model.handle(action) }
                case .dictation, .ignore:
                    break
                }
            },
            onError: { [weak self] message in self?.showHotkeyError(message) }
        )
        self.listener = listener
        listener.start()

        settingsDependencies = SettingsModel.Dependencies(
            store: configStore,
            secrets: secrets,
            hotkeys: listener,
            sounds: sounds,
            updates: SparkleUpdateChecking(),
            platform: PlatformInfo(),
            assetStatus: { await SpeechModelAssets.status(api: analyzer) },
            installAssets: { try await SpeechModelAssets.install(api: analyzer) },
            prompts: prompts,
            apps: NSWorkspaceApps(),
            pruneHistory: { [retentionDays] days in
                // The retention the store reads is applied here rather than waiting for
                // the config-change stream, so retention 0 deletes the file at once (F29).
                retentionDays.withLock { $0 = days }
                try? await history.prune()
            },
            clearHistory: { try? await history.clear() },
            openHistory: { [weak self] in self?.openHistory() },
            openCorrection: { [weak self] source in self?.openCorrection(source) }
        )

        historyDependencies = HistoryListModel.Dependencies(
            history: history,
            paster: paster,
            pasteboard: NSPasteboardAccess(),
            isRunning: { processes.isRunning(pid: $0) },
            retentionDays: { [retentionDays] in retentionDays.withLock { $0 } },
            clock: SystemClock(),
            now: { Date() },
            hide: { [weak self] in self?.historyWindow?.hide() },
            activate: { target in NSRunningApplication(processIdentifier: target.pid)?.activate() },
            correct: { [weak self] source in self?.openCorrection(source) }
        )

        correctionDependencies = CorrectionModel.Dependencies(
            store: configStore,
            pasteboard: NSPasteboardAccess(),
            historyEntries: { [retentionDays] in
                // R31: retention 0 is "no preview", which an empty history is not.
                guard retentionDays.withLock({ $0 }) > 0 else { return nil }
                return await history.search("").map {
                    ImpactPreview.Entry(text: $0.text, bundleID: $0.bundleID)
                }
            }
        )

        configTask = Task { [weak self] in
            for await updated in configStore.changes {
                self?.apply(updated)
            }
        }
        Log.ui.info("Started; bindings \(config.hotkey) / \(config.submitHotkey)")

        if (try? secrets.secret(for: .openai))?.isEmpty ?? true {
            firstRunSettings()
        }
        await promptForSpeechModelIfNeeded(configStore: configStore)
    }

    /// Design §5.3: one `MeetingController` per meeting window, sharing the dictation capture
    /// engine, which is free while a meeting holds it because dictation is locked out (R19).
    private func makeMeetings(
        audio: AudioCaptureEngine,
        secrets: KeychainStore,
        configStore: ConfigStore,
        usage: UsageStore,
        prompts: PromptFiles
    ) -> MeetingCoordinator {
        let store = MeetingStore(directory: Self.configDirectory.appendingPathComponent("meetings", isDirectory: true))
        let summarizer = KeyedAnthropicClient(secrets: secrets)
        return MeetingCoordinator(deps: MeetingCoordinator.Dependencies(
            makeController: { frontApp in
                MeetingController(
                    deps: MeetingDependencies(
                        audio: audio,
                        tapFactory: CoreAudioTapFactory(),
                        engines: EngineFactory(),
                        secrets: secrets,
                        store: store,
                        summarizer: summarizer,
                        usage: usage,
                        prompts: prompts,
                        frontAppName: { frontApp },
                        userName: { NSFullUserName() }
                    ),
                    config: configStore
                )
            },
            frontApp: {
                guard let app = NSWorkspace.shared.frontmostApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                else { return nil }
                return app.localizedName
            },
            chooser: { [weak self] in
                MeetingWindowModel.Chooser(
                    config: self?.config ?? Config(),
                    platform: PlatformInfo(),
                    accountName: NSFullUserName(),
                    hasKey: { (try? secrets.secret(for: $0))?.isEmpty == false }
                )
            },
            makeWindow: { model, actions in MeetingWindowController(model: model, actions: actions) },
            now: { Date() },
            endDictation: { [weak self] in await self?.controller?.abort() },
            openSettings: { [weak self] in self?.openSettings() },
            changed: { [weak self] in self?.meetingChanged(usage: usage) }
        ))
    }

    /// The menu follows the meeting; Stop and the summary add usage (R18).
    private func meetingChanged(usage: UsageStore) {
        statusItem?.setMeetingActive(meetings?.isActive ?? false)
        Task { [weak self] in
            let totals = await usage.totals()
            self?.statusItem?.setUsage(today: totals.today, monthCost: totals.monthCost)
        }
    }

    /// §5.5 Launch: with no OpenAI key stored, the source opens Settings a second
    /// after normal start.
    private func firstRunSettings() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            Log.ui.info("No OpenAI key stored; opening Settings")
            await openSettingsWindow()
        }
    }

    private func openSettings() {
        Task { await openSettingsWindow() }
    }

    /// Like Settings, History needs the stores, so it only opens once normal
    /// operation has started (F29).
    private func openHistory() {
        guard let dependencies = historyDependencies else { return }
        if historyWindow == nil {
            historyWindow = HistoryWindowController(
                model: HistoryListModel(deps: dependencies),
                frontmost: NSWorkspaceFrontmostApp()
            )
        }
        historyWindow?.show()
    }

    /// R27: the last delivered dictation is the menu bar's own, so the window opens
    /// even with history retention at 0.
    private func correctLast() {
        guard let dictation = statusItem?.lastDictation else { return }
        openCorrection(CorrectionSource(dictation))
    }

    /// R27/R28: one window, whichever entry point opened it.
    private func openCorrection(_ source: CorrectionSource) {
        guard let dependencies = correctionDependencies else { return }
        if correctionWindow == nil {
            correctionWindow = CorrectionWindowController(deps: dependencies)
        }
        correctionWindow?.show(source: source)
    }

    /// Settings needs the live listener and stores, so it only opens once normal
    /// operation has started — the guard `app.py:_open_settings` also has.
    private func openSettingsWindow() async {
        guard let dependencies = settingsDependencies else { return }
        if settings == nil {
            settings = SettingsWindowController(
                model: SettingsModel(config: await dependencies.store.load(), deps: dependencies)
            )
        }
        settings?.show()
    }

    /// F32's one-time dialog, asked after normal start so the app is already usable.
    private func promptForSpeechModelIfNeeded(configStore: ConfigStore) async {
        let analyzer = SpeechAnalyzerBridge()
        let status = await SpeechModelAssets.status(api: analyzer)
        guard SpeechModelPrompt.shouldPrompt(
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            status: status,
            alreadyPrompted: await configStore.load().speechModelPrompted
        ) else { return }

        let prompt = SpeechModelPrompt(
            install: { try await SpeechModelAssets.install(api: analyzer) },
            markPrompted: { try? await configStore.update { $0.speechModelPrompted = true } }
        )
        await prompt.choose(SpeechModelPrompt.ask())
    }

    /// Every config value the app itself holds a copy of (F19). The stores read the
    /// rest through `ConfigStore` directly.
    private func apply(_ config: Config) {
        self.config = config
        // R36: the one config-change consumer there is, so an open Settings window sees
        // a rule the correction window just saved (N4).
        settings?.model.refresh(from: config)
        sounds.setVolume(Float(config.soundVolume))
        // R3: stored now, honoured at the card's next show.
        overlay?.setStyle(config.overlayStyle)
        if appliedOverlayStyle != config.overlayStyle {
            appliedOverlayStyle = config.overlayStyle
            Log.ui.info("Overlay style: \(config.overlayStyle.rawValue)")
        }
        retentionDays.withLock { $0 = config.historyRetentionDays }
        let bindings = Self.bindings(from: config)
        for (name, combo) in bindings where appliedBindings[name] != combo {
            // Only on a real change: `update` resets the matcher, and the config file is
            // rewritten after every dictation when usage is recorded.
            listener?.update(binding: name, combo: combo)
        }
        appliedBindings = bindings
    }

    /// F8's two bindings and the meeting toggle, falling back to the shipped defaults
    /// when a stored combo no longer parses. A meeting combo equal to a dictation one
    /// falls back too (design §5.7), and is dropped if the default clashes as well.
    static func bindings(from config: Config) -> [BindingName: HotkeyCombo] {
        let configured: [(BindingName, String, String)] = [
            (.paste, config.hotkey, "shift+cmd_r"),
            (.pasteSubmit, config.submitHotkey, "cmd_r"),
            (.meeting, config.meetingHotkey, "ctrl+alt+cmd+m"),
        ]
        return configured.reduce(into: [:]) { bindings, entry in
            let (name, stored, fallback) = entry
            // Dictation keeps its pre-meeting behaviour; only the meeting toggle yields.
            let taken = name == .meeting ? Set(bindings.values) : []
            if let combo = try? HotkeyCombo.parse(stored), !taken.contains(combo) {
                bindings[name] = combo
            } else if let combo = try? HotkeyCombo.parse(fallback), !taken.contains(combo) {
                Log.hotkey.warning("Unparsable or duplicate \(name.rawValue) hotkey; using \(fallback)")
                bindings[name] = combo
            }
        }
    }

    private static func bundledPrompt(_ name: String) -> URL {
        Bundle.main.url(forResource: name, withExtension: "txt")
            ?? Bundle.main.bundleURL.appendingPathComponent("\(name).txt")
    }

    private func showHotkeyError(_ message: String) {
        Log.hotkey.error("\(message)")
        router?.show(error: message)
    }

    // MARK: - Lifecycle

    private func configureLogging() {
        let arguments = LaunchArguments()
        Log.configure(
            debug: arguments.debug,
            sinks: arguments.debug ? [FileLogSink(url: LaunchArguments.debugLogURL)] : []
        )
        Log.ui.info("Mini Whisper launched (debug: \(arguments.debug))")
    }

    /// ⌘Q and logout (§5.7 Quit while recording); the menu's Quit asks in `quit()`.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let meetings, meetings.needsQuitConfirmation else { return .terminateNow }
        guard Self.confirmQuitDuringMeeting() else { return .terminateCancel }
        Task {
            await meetings.stop(summarise: false)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Stop runs without the summary, which can be asked for later.
    private static func confirmQuitDuringMeeting() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "A meeting is recording. Stop and quit?"
        alert.informativeText = "The meeting is saved without a summary; you can summarise it later."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func quit() {
        Task { @MainActor in
            if let meetings, meetings.needsQuitConfirmation {
                guard Self.confirmQuitDuringMeeting() else { return }
                await meetings.stop(summarise: false)
            }
            configTask?.cancel()
            settings?.close()
            historyWindow?.hide()
            correctionWindow?.hide()
            await controller?.abort()
            router?.stop()
            listener?.stop()
            await audio?.stop()
            NSApp.terminate(nil)
        }
    }
}
