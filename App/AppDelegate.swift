import AppKit
import MWAudio
import MWConfig
import MWHistory
import MWHotkeys
import MWPaste
import MWPipeline
import MWOverlaySim
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
    private var appliedBindings: [BindingName: HotkeyCombo] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The AppTests bundle is hosted by this app; starting normally there would
        // touch the user's config, Keychain and input devices.
        guard !LaunchArguments.isRunningTests else { return }

        guard SingleInstanceGuard.claim() else { exit(0) }
        configureLogging()

        let permitted = PermissionMonitor.allGranted
        statusItem = StatusItemController(
            sounds: sounds,
            onHistory: { Log.ui.info("History window arrives in Stage 29") },
            onSettings: { Log.ui.info("Settings window arrives in Stage 27") },
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
        let audio = AudioCaptureEngine(backend: AVAudioEngineBackend())
        self.audio = audio
        let usage = UsageStore(config: configStore)
        let openAI = KeyedOpenAIClient(secrets: secrets)
        let deps = Dependencies(
            audio: audio,
            engines: EngineFactory(),
            frontmost: NSWorkspaceFrontmostApp(),
            transcriber: openAI,
            cleaner: openAI,
            paster: Paster(
                pasteboard: NSPasteboardAccess(),
                poster: CGEventKeyPoster(),
                accessibility: AXTrustCheck(),
                process: RunningProcessCheck(),
                clock: SystemClock()
            ),
            secrets: secrets,
            usage: usage,
            history: HistoryStore(
                url: Self.configDirectory.appendingPathComponent("history.jsonl"),
                retention: { [retentionDays] in retentionDays.withLock { $0 } }
            ),
            sounds: sounds,
            prompts: PromptFiles(
                directory: Self.configDirectory,
                bundledCleanup: Self.bundledPrompt("default_prompt"),
                bundledTranscribe: Self.bundledPrompt("default_transcribe_prompt")
            )
        )

        let controller = DictationController(deps: deps, config: configStore)
        self.controller = controller

        if let statusItem {
            // §5.5: the panels exist off-screen before the first press.
            let overlay = OverlayPanelController(
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
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
            onAction: { [weak controller] action in
                switch action {
                case .pressed(let name): controller?.hotkeyPressed(name)
                case .released(let name): controller?.hotkeyReleased(name)
                // Capture belongs to the Settings hotkey fields (Stage 27).
                case .captured, .captureRejected: break
                }
            },
            onError: { [weak self] message in self?.showHotkeyError(message) }
        )
        self.listener = listener
        listener.start()

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

    /// §5.5 Launch: with no OpenAI key stored, the source opens Settings a second
    /// after normal start.
    private func firstRunSettings() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            Log.ui.info("No OpenAI key stored; Settings auto-open arrives in Stage 27")
        }
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
        sounds.setVolume(Float(config.soundVolume))
        retentionDays.withLock { $0 = config.historyRetentionDays }
        let bindings = Self.bindings(from: config)
        for (name, combo) in bindings where appliedBindings[name] != combo {
            // Only on a real change: `update` resets the matcher, and the config file is
            // rewritten after every dictation when usage is recorded.
            listener?.update(binding: name, combo: combo)
        }
        appliedBindings = bindings
    }

    /// F8's two bindings, falling back to the shipped defaults when a stored combo no
    /// longer parses.
    private static func bindings(from config: Config) -> [BindingName: HotkeyCombo] {
        let configured: [(BindingName, String, String)] = [
            (.paste, config.hotkey, "shift+cmd_r"),
            (.pasteSubmit, config.submitHotkey, "cmd_r"),
        ]
        return configured.reduce(into: [:]) { bindings, entry in
            let (name, stored, fallback) = entry
            if let combo = try? HotkeyCombo.parse(stored) {
                bindings[name] = combo
            } else if let combo = try? HotkeyCombo.parse(fallback) {
                Log.hotkey.warning("Unparsable \(name.rawValue) hotkey; using \(fallback)")
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

    private func quit() {
        Task { @MainActor in
            configTask?.cancel()
            await controller?.abort()
            router?.stop()
            listener?.stop()
            await audio?.stop()
            NSApp.terminate(nil)
        }
    }
}
