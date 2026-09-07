import Foundation
import MWConfig
import MWHotkeys
import MWStreaming
import MWSupport
import Observation

/// The live hotkey matcher's capture mode (F7), as Settings needs it. One
/// conformer: `GlobalKeyListener`.
protocol HotkeyCapturing: AnyObject, Sendable {
    func beginCapture()
    func cancelCapture()
    func update(binding: BindingName, combo: HotkeyCombo)
}

/// Sparkle's automatic-check preference and its manual check. One conformer:
/// `SparkleUpdateChecking`. Sparkle reads and writes this setting itself on every
/// scheduled check, so it is the one preference that is not in `config.json`.
protocol UpdateChecking: AnyObject, Sendable {
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}

/// The volume preview of F34. One conformer: `SoundPlayer`.
protocol SoundPreviewing: AnyObject, Sendable {
    func setVolume(_ volume: Float)
    func playOn()
}

/// Everything the Settings window can do to the rest of the app, and the only
/// place its rules live (design §5.4). The views are thin: they read the
/// published state and call the `async` mutators, each of which writes through
/// to `config.json` immediately, as the source does.
@MainActor
@Observable
final class SettingsModel {
    struct Dependencies {
        var store: ConfigStore
        var secrets: any SecretStore
        var hotkeys: any HotkeyCapturing
        var sounds: any SoundPreviewing
        var updates: any UpdateChecking
        var platform: PlatformInfo
        var assetStatus: @Sendable () async -> AssetStatus
        var installAssets: @Sendable () async throws -> Void
        var prompts: PromptFiles
        var apps: any AppListing
        /// Applies the new retention and prunes; retention 0 deletes the file (F29).
        var pruneHistory: @Sendable (Int) async -> Void
        var clearHistory: @Sendable () async -> Void
        var openHistory: @MainActor () -> Void
        /// R35: the tally's Remember… seeds the correction window rather than adding a
        /// second rule-entry form.
        var openCorrection: @MainActor (CorrectionSource) -> Void
    }

    enum Section: String, CaseIterable, Identifiable {
        case general, hotkeys, keys, cleanup, vocabulary, history, sound

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .hotkeys: "Hotkeys"
            case .keys: "Keys"
            case .cleanup: "Cleanup"
            case .vocabulary: "Vocabulary"
            case .history: "History"
            case .sound: "Sound"
            }
        }

        var symbolName: String {
            switch self {
            case .general: "gearshape"
            case .hotkeys: "command"
            case .keys: "key"
            case .cleanup: "wand.and.sparkles"
            case .vocabulary: "textformat.abc"
            case .history: "clock.arrow.circlepath"
            case .sound: "speaker.wave.2"
            }
        }
    }

    enum EngineAccessory: Equatable {
        case download
        case installing(fraction: Double)
        case installed

        var text: String {
            switch self {
            case .download: "Download model…"
            case .installing(let fraction):
                fraction > 0 ? "Downloading… \(Int((fraction * 100).rounded()))%" : "Downloading…"
            case .installed: "Installed"
            }
        }
    }

    struct EngineRow: Identifiable, Equatable {
        var name: EngineName
        var title: String
        var subtitle: String?
        var isEnabled: Bool
        var disabledReason: String?
        var accessory: EngineAccessory?

        var id: EngineName { name }
    }

    static let idleStopSecondsRange = 10...600
    static let retentionDaysRange = 0...30
    static let toggleCapMinutesRange = 1...30
    static let capturePlaceholder = "Press shortcut..."
    static let dotMask = "••••••••••••"

    private let deps: Dependencies

    private(set) var config: Config
    private(set) var speechModel: AssetStatus = .unavailable
    private(set) var capturing: BindingName?
    private(set) var keyErrors: [KeyAccount: String] = [:]

    /// The slider's live value; `commitVolume()` is what writes and previews (F34).
    var volume: Double
    var selection: Section = .general

    let vocabulary: VocabularyModel
    let profiles: ProfilesEditorModel
    let corrections: CorrectionsEditorModel

    /// The two prompt files, read when the Cleanup pane first appears.
    var cleanupPromptDraft = ""
    var transcribeDraft = ""
    private(set) var promptError: String?

    private var masks: [KeyAccount: String] = [:]
    private var displays: [BindingName: String] = [:]
    private var previousDisplay: String?

    /// Mirrors Sparkle's preference so the Settings toggle is observable.
    var automaticUpdatesEnabled: Bool

    init(config: Config, deps: Dependencies) {
        self.config = config
        self.deps = deps
        volume = config.soundVolume
        automaticUpdatesEnabled = deps.updates.automaticallyChecksForUpdates
        vocabulary = VocabularyModel(terms: config.vocabulary, store: deps.store)
        profiles = ProfilesEditorModel(
            config: config,
            store: deps.store,
            apps: deps.apps,
            defaultPrompt: { (try? deps.prompts.cleanupPrompt()) ?? "" }
        )
        corrections = CorrectionsEditorModel(
            config: config,
            store: deps.store,
            apps: deps.apps,
            openCorrection: deps.openCorrection
        )
        refreshKeys()
        for binding in BindingName.allCases {
            displays[binding] = Self.displayString(of: stored(binding))
        }
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    func setAutomaticUpdates(_ enabled: Bool) {
        deps.updates.automaticallyChecksForUpdates = enabled
        automaticUpdatesEnabled = enabled
    }

    func checkForUpdatesNow() {
        deps.updates.checkForUpdates()
    }

    /// R36: a config written elsewhere — the correction window, or the Python app —
    /// reaches the open panes through AppDelegate's single config-change consumer (N4).
    func refresh(from config: Config) {
        self.config = config
        vocabulary.replace(terms: config.vocabulary)
        corrections.refresh(config)
        profiles.setDefaultCleanup(config.cleanupEnabled)
    }

    // MARK: - General

    /// The row the radio list marks. An absent `streaming_engine` — every config
    /// written by the Python app — is not "no engine": a press would run F32's
    /// platform default, so that is what the list shows.
    var selectedEngine: EngineName {
        config.streamingEngine ?? EngineFactory.defaultEngine(
            platform: deps.platform,
            assetsInstalled: speechModel == .installed
        )
    }

    var engineRows: [EngineRow] {
        var rows: [EngineRow] = []
        if deps.platform.osMajor >= 26, let accessory = analyzerAccessory {
            rows.append(EngineRow(
                name: .speechAnalyzer,
                title: "SpeechAnalyzer",
                subtitle: "On-device · macOS 26 · best accuracy",
                isEnabled: true,
                accessory: accessory
            ))
        }
        rows.append(EngineRow(
            name: .onDevice,
            title: "On-device (Apple Speech)",
            subtitle: "Free, offline",
            isEnabled: true
        ))
        for (name, account, title, reason) in Self.cloudEngines {
            let hasKey = !mask(for: account).isEmpty
            rows.append(EngineRow(
                name: name,
                title: title,
                isEnabled: hasKey,
                disabledReason: hasKey ? nil : reason
            ))
        }
        return rows
    }

    /// Nil hides the row: below macOS 26, or when the model is unavailable for this
    /// locale, choosing it would silently fall back to SFSpeechRecognizer (F23).
    private var analyzerAccessory: EngineAccessory? {
        switch speechModel {
        case .unavailable: nil
        case .notInstalled: .download
        case .installing(let fraction): .installing(fraction: fraction)
        case .installed: .installed
        }
    }

    private static let cloudEngines: [(EngineName, KeyAccount, String, String)] = [
        (.openai, .openai, "OpenAI Realtime", "Add an OpenAI key under Keys to enable"),
        (.elevenlabs, .elevenlabs, "ElevenLabs", "Add an ElevenLabs key under Keys to enable"),
        (.speechmatics, .speechmatics, "Speechmatics", "Add a Speechmatics key under Keys to enable"),
    ]

    var idleStopLabel: String { "\(config.idleStopSeconds) s" }
    var toggleCapLabel: String { "\(config.toggleMaxSeconds / 60) min" }

    func setStreamingEnabled(_ enabled: Bool) async {
        await write { $0.streamingEnabled = enabled }
    }

    func selectEngine(_ name: EngineName) async {
        guard engineRows.first(where: { $0.name == name })?.isEnabled == true else { return }
        await write { $0.streamingEngine = name }
    }

    func setIdleStopSeconds(_ seconds: Int) async {
        let value = seconds.clamped(to: Self.idleStopSecondsRange)
        await write { $0.idleStopSeconds = value }
    }

    func setToggleCapMinutes(_ minutes: Int) async {
        let value = minutes.clamped(to: Self.toggleCapMinutesRange) * 60
        await write { $0.toggleMaxSeconds = value }
    }

    func refreshSpeechModel() async {
        speechModel = await deps.assetStatus()
    }

    func installSpeechModel() async {
        // The row reports the download from the press, not from its completion:
        // `installAssets` only returns once the model is on disk.
        speechModel = .installing(fractionCompleted: 0)
        do {
            try await deps.installAssets()
        } catch {
            Log.ui.error("Speech model download failed: \(AnyError(error).description)")
        }
        await refreshSpeechModel()
    }

    // MARK: - Cleanup (F26)

    /// Without an OpenAI key the toggle cannot be moved, so the stored value is
    /// never rewritten by the gating.
    var cleanupToggleEnabled: Bool { !mask(for: .openai).isEmpty }
    var cleanupShownOn: Bool { config.cleanupEnabled && cleanupToggleEnabled }

    func setCleanupEnabled(_ enabled: Bool) async {
        guard cleanupToggleEnabled else { return }
        await write { $0.cleanupEnabled = enabled }
    }

    // MARK: - Prompts (F26 editors)

    var cleanupPromptURL: URL { deps.prompts.cleanupPromptURL }
    var transcribeInstructionsURL: URL { deps.prompts.transcribeInstructionsURL }

    func loadPrompts() {
        cleanupPromptDraft = (try? deps.prompts.cleanupPrompt()) ?? ""
        transcribeDraft = (try? deps.prompts.transcribeInstructions()) ?? ""
    }

    func saveCleanupPrompt() {
        save { try deps.prompts.write(cleanupPrompt: cleanupPromptDraft) }
    }

    func saveTranscribeInstructions() {
        save { try deps.prompts.write(transcribeInstructions: transcribeDraft) }
    }

    private func save(_ write: () throws -> Void) {
        do {
            try write()
            promptError = nil
        } catch {
            promptError = AnyError(error).description
            Log.config.error("Could not save prompt: \(AnyError(error).description)")
        }
    }

    // MARK: - History (F29)

    static func retentionLabel(days: Int) -> String {
        days == 0 ? "Off" : "\(days) days"
    }

    func setRetentionDays(_ days: Int) async {
        let value = days.clamped(to: Self.retentionDaysRange)
        await write { $0.historyRetentionDays = value }
        await deps.pruneHistory(value)
    }

    func clearHistory() async {
        await deps.clearHistory()
    }

    func openHistory() {
        deps.openHistory()
    }

    // MARK: - Keys (F3)

    func mask(for account: KeyAccount) -> String {
        masks[account] ?? ""
    }

    func error(for account: KeyAccount) -> String? {
        keyErrors[account]
    }

    /// Re-reads which accounts hold a key and rebuilds their masks. The key itself
    /// is never held, displayed beyond its last four characters, or logged.
    func refreshKeys() {
        for account in KeyAccount.allCases {
            let secret = (try? deps.secrets.secret(for: account)).flatMap { $0 }
            masks[account] = secret.map { Self.mask(of: $0, account: account) } ?? ""
        }
    }

    func saveKey(_ account: KeyAccount, value: String) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != mask(for: account) else {
            keyErrors[account] = "Enter a new API key to save."
            return
        }
        if account == .openai, !key.hasPrefix("sk-") {
            keyErrors[account] = "Invalid key — must start with 'sk-'."
            return
        }
        do {
            try deps.secrets.setSecret(key, for: account)
        } catch {
            keyErrors[account] = AnyError(error).description
            return
        }
        keyErrors[account] = nil
        masks[account] = Self.mask(of: key, account: account)
    }

    private static func mask(of secret: String, account: KeyAccount) -> String {
        guard account == .openai else { return dotMask }
        return "sk-…\(secret.suffix(4))"
    }

    // MARK: - Hotkeys (F7)

    func display(_ binding: BindingName) -> String {
        displays[binding] ?? ""
    }

    func beginCapture(_ binding: BindingName) {
        if capturing != nil { cancelCapture() }
        capturing = binding
        previousDisplay = display(binding)
        displays[binding] = Self.capturePlaceholder
        deps.hotkeys.beginCapture()
    }

    func cancelCapture() {
        guard let binding = capturing else { return }
        deps.hotkeys.cancelCapture()
        displays[binding] = previousDisplay ?? ""
        capturing = nil
        previousDisplay = nil
    }

    /// The capture half of the listener's actions. A rejected combo leaves the
    /// matcher in capture mode, so the field simply keeps waiting.
    func handle(_ action: HotkeyAction) async {
        guard let binding = capturing else { return }
        switch action {
        case .captured(let combo):
            displays[binding] = combo.displayString
            capturing = nil
            previousDisplay = nil
            deps.hotkeys.update(binding: binding, combo: combo)
            await write { config in
                switch binding {
                case .paste: config.hotkey = combo.configString
                case .pasteSubmit: config.submitHotkey = combo.configString
                }
            }
        case .captureRejected, .pressed, .released:
            break
        }
    }

    private func stored(_ binding: BindingName) -> String {
        switch binding {
        case .paste: config.hotkey
        case .pasteSubmit: config.submitHotkey
        }
    }

    /// An unparsable stored combo is shown verbatim, as `settings.py` does.
    private static func displayString(of combo: String) -> String {
        (try? HotkeyCombo.parse(combo).displayString) ?? combo
    }

    // MARK: - Sound (F34)

    func commitVolume() async {
        let rounded = (volume * 100).rounded() / 100
        volume = rounded
        await write { $0.soundVolume = rounded }
        deps.sounds.setVolume(Float(rounded))
        deps.sounds.playOn()
    }

    // MARK: - Write-through

    private func write(_ mutate: @escaping @Sendable (inout Config) -> Void) async {
        do {
            try await deps.store.update(mutate)
        } catch {
            Log.config.error("Could not save settings: \(AnyError(error).description)")
        }
        config = await deps.store.load()
        profiles.setDefaultCleanup(config.cleanupEnabled)
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
