import Foundation
import MWConfig
import MWHotkeys
import MWMeetings
import MWNaming
import MWOverlaySim
import MWStreaming
import MWSupport
import MWUsage
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

/// Everything the Settings page can do to the rest of the app, and the only
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
        /// R35: the tally's Remember… seeds the correction window rather than adding a
        /// second rule-entry form.
        var openCorrection: @MainActor (CorrectionSource) -> Void
        /// R20: stands in for a blank `meeting_user_name`, as in `MeetingController`.
        var accountName: String = NSFullUserName()
        var meetingIndex: @Sendable () async -> [IndexEntry] = { [] }
        var showMeetingsFolder: @MainActor () -> Void = {}
        var installTool: @MainActor () -> Result<Void, CommandLineToolInstaller.Failure> = {
            .failure(CommandLineToolInstaller.Failure(message: "Install is unavailable."))
        }
        var isToolInstalled: @Sendable () -> Bool = { false }
        var toolBinaryPath: String = Bundle.main.executablePath ?? ""
        var copy: @MainActor (String) -> Void = { _ in }
        /// Loads the bundled voice model; false when it cannot be loaded on this Mac.
        var prepareVoiceModel: @Sendable () async -> Bool = { true }
        var people = PeopleModel.Dependencies()
        /// Injected so a test can run as a beta build (design v10 R8).
        var appVersion: String =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    enum Section: String, CaseIterable, Identifiable {
        case general, hotkeys, keys, cleanup, vocabulary, history, meetings, people, overlay, sound

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .hotkeys: "Hotkeys"
            case .keys: "Keys"
            case .cleanup: "Cleanup"
            case .vocabulary: "Vocabulary"
            case .history: "Dictations"
            case .meetings: "Meetings"
            case .people: "People"
            case .overlay: "Overlay"
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
            case .meetings: "person.2.wave.2"
            case .people: "person.crop.circle"
            case .overlay: "sparkles.rectangle.stack"
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

    struct MeetingEngineRow: Identifiable, Equatable {
        var engine: MeetingEngine
        var title: String
        var subtitle: String
        var price: String
        var isEnabled: Bool
        var disabledReason: String?

        var id: MeetingEngine { engine }
    }

    struct OverlayStyleRow: Identifiable, Equatable {
        var style: OverlayStyle
        var title: String
        var summary: String
        var isDefault: Bool

        var id: OverlayStyle { style }
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
    private var hotkeyErrors: [BindingName: String] = [:]

    /// The slider's live value; `commitVolume()` is what writes and previews (F34).
    var volume: Double
    /// Leaving Hotkeys gives a capture under way back to the previous combo (R22).
    var selection: Section = .general {
        didSet {
            if oldValue == .hotkeys, selection != .hotkeys { cancelCapture() }
        }
    }

    let vocabulary: VocabularyModel
    let profiles: ProfilesEditorModel
    let corrections: CorrectionsEditorModel
    let people: PeopleModel

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
        people = PeopleModel(deps: deps.people)
        refreshKeys()
        for binding in BindingName.allCases {
            displays[binding] = Self.displayString(of: stored(binding))
        }
    }

    /// R36: a config written elsewhere — the correction window, or the Python app —
    /// reaches the open panes through AppDelegate's single config-change consumer (N4).
    func refresh(from config: Config) {
        self.config = config
        vocabulary.replace(terms: config.vocabulary)
        corrections.refresh(config)
        profiles.setDefaultCleanup(config.cleanupEnabled)
    }

    // MARK: - Updates (design v10)

    var appVersion: String { deps.appVersion }

    /// R8: the version line marks a beta build.
    var isBetaBuild: Bool { UpdateChannelPolicy.isBeta(version: appVersion) }

    func setAutomaticUpdates(_ enabled: Bool) {
        deps.updates.automaticallyChecksForUpdates = enabled
        automaticUpdatesEnabled = enabled
    }

    func checkForUpdatesNow() {
        deps.updates.checkForUpdates()
    }

    /// The stored channel, so a pending confirmation leaves the pill on Release.
    var updateChannel: UpdateChannel { config.updateChannel }

    /// While true, `MainView` shows the Beta dialog.
    private(set) var confirmingBetaChannel = false

    /// R3: Beta waits for the dialog. R4: Release is written at once. `AppDelegate`'s
    /// config-change consumer hands the stored channel to Sparkle.
    func chooseUpdateChannel(_ channel: UpdateChannel) async {
        guard channel != updateChannel else { return }
        switch channel {
        case .beta: confirmingBetaChannel = true
        case .release: await write { $0.updateChannel = .release }
        }
    }

    func confirmBetaChannel() async {
        confirmingBetaChannel = false
        await write { $0.updateChannel = .beta }
    }

    func cancelBetaChannel() {
        confirmingBetaChannel = false
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
            let keyed = hasKey(account)
            rows.append(EngineRow(
                name: name,
                title: title,
                isEnabled: keyed,
                disabledReason: keyed ? nil : reason
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
        (.assemblyai, .assemblyai, "AssemblyAI", "Add an AssemblyAI key under Keys to enable"),
    ]

    private static func keyHint(for account: KeyAccount) -> String? {
        cloudEngines.first { $0.1 == account }?.3
    }

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
    var cleanupToggleEnabled: Bool { hasKey(.openai) }
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

    // MARK: - Meetings (design v4 §3 R4, R20, R22)

    static let privacySettingsURL = MeetingWindowModel.privacySettingsURL

    var meetingEngineRows: [MeetingEngineRow] {
        MeetingEngine.allCases.map { engine in
            let keyed = hasKey(engine.keyAccount)
            return MeetingEngineRow(
                engine: engine,
                title: engine.title,
                subtitle: Self.subtitle(of: engine),
                price: Self.price(of: engine, overrides: config.pricingOverrides),
                isEnabled: keyed,
                disabledReason: keyed ? nil : Self.keyHint(for: engine.keyAccount)
            )
        }
    }

    /// The tier a meeting would use. A stored tier without its key stays in the config,
    /// shown disabled, while the first keyed tier is used (design §5.7).
    var activeMeetingEngine: MeetingEngine? {
        MeetingEngine.resolve(stored: config.meetingEngine, hasKey: hasKey)
    }

    func selectMeetingEngine(_ engine: MeetingEngine) async {
        guard hasKey(engine.keyAccount) else { return }
        await write { $0.meetingEngine = engine }
    }

    var meetingUserName: String {
        config.meetingUserName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            ?? deps.accountName
    }

    /// A blank name is stored as absent, so the account name applies again.
    func setMeetingUserName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await write { $0.meetingUserName = trimmed.isEmpty ? nil : trimmed }
    }

    func setMeetingKeepAudio(_ keep: Bool) async {
        await write { $0.meetingKeepAudio = keep }
    }

    func setMeetingSilenceStop(_ seconds: Int) async {
        await write { $0.meetingSilenceStopSeconds = seconds }
    }

    static func silenceStopDescription(_ seconds: Int) -> String {
        guard seconds > 0 else { return "Off: a meeting records until you stop it." }
        return "When no one has spoken for \(seconds / 60) min, asks whether to keep recording and stops a minute"
            + " later. Never in a meeting's first 3 minutes."
    }

    var summaryPromptDraft = ""
    var summaryPromptURL: URL { deps.prompts.summaryPromptURL }

    var summaryKeyHint: String? {
        hasKey(.anthropic) ? nil : "Add an Anthropic key under Keys to enable."
    }

    func loadSummaryPrompt() {
        summaryPromptDraft = (try? deps.prompts.summaryPrompt()) ?? ""
    }

    func saveSummaryPrompt() {
        save { try deps.prompts.write(summaryPrompt: summaryPromptDraft) }
    }

    func restoreDefaultSummaryPrompt() {
        save { try deps.prompts.restoreDefaultSummaryPrompt() }
        loadSummaryPrompt()
    }

    /// "12 meetings · 310 MB audio", as the Meetings page's footer reads.
    private(set) var storageText = ""
    private var toolInstalled = false
    private var toolError: String?

    /// Re-reads what the pane shows from outside the config: the index and the installed tool.
    func refreshMeetings() async {
        let entries = await deps.meetingIndex()
        let audio = entries.reduce(0) { $0 + $1.audioBytes }
        let count = "\(entries.count) meeting\(entries.count == 1 ? "" : "s")"
        storageText = audio > 0 ? "\(count) · \(Self.size(audio)) audio" : count
        toolInstalled = deps.isToolInstalled()
        toolError = nil
    }

    func showMeetingsFolder() {
        deps.showMeetingsFolder()
    }

    /// R22: the row reports success, or the installer's reason such as "User canceled.".
    var toolStatus: String {
        toolError ?? (toolInstalled ? "Installed" : "Not installed")
    }

    func installTool() {
        switch deps.installTool() {
        case .success:
            toolInstalled = true
            toolError = nil
        case .failure(let failure):
            toolError = failure.message
        }
    }

    var claudeCodeCommand: String {
        CommandLineToolInstaller.mcpCommand(installed: toolInstalled, binaryPath: deps.toolBinaryPath)
    }

    func copyClaudeCodeCommand() {
        deps.copy(claudeCodeCommand)
    }

    var chatGPTCommand: String {
        CommandLineToolInstaller.chatGPTCommand(installed: toolInstalled, binaryPath: deps.toolBinaryPath)
    }

    func copyChatGPTCommand() {
        deps.copy(chatGPTCommand)
    }

    private static func subtitle(of engine: MeetingEngine) -> String {
        switch engine {
        case .speechmaticsStandard: "Speaker labels included · English"
        case .speechmaticsEnhanced: "Higher accuracy · speaker labels included"
        case .assemblyaiStreaming: "Speaker labels add-on · English"
        case .assemblyaiPro: "Higher accuracy · speaker labels add-on"
        }
    }

    /// "$0.45/h"; AssemblyAI's speaker-labels add-on is shown as a second figure, as in the mockup.
    private static func price(of engine: MeetingEngine, overrides: [String: Double]) -> String {
        let hour = Pricing.perHour(engine, overrides: overrides)
        guard let key = engine.diarizationPricingKey else { return "\(Pricing.dollars(hour))/h" }
        let addOn = Pricing.rate(Pricing.perMinute, key: key, overrides: overrides) * 60
        return "\(Pricing.dollars(hour - addOn)) + \(Pricing.dollars(addOn))/h"
    }

    /// Decimal megabytes, as Finder and the Meetings page show them.
    private static func size(_ bytes: Int) -> String {
        bytes >= 1_000_000_000
            ? String(format: "%.1f GB", Double(bytes) / 1e9)
            : "\(max(1, Int((Double(bytes) / 1e6).rounded()))) MB"
    }

    // MARK: - Voices (design v8 §3 R1, R3, R4)

    enum VoiceModelStatus: Equatable {
        case ready
        case failed
    }

    /// The slider's caption: the step's name, which the row sets in bold, and what the step does.
    struct VoiceCaption: Equatable {
        var name: String
        var detail: String
    }

    private static let balancedVoiceStep = 5

    /// Nil until the Meetings section first appears.
    private(set) var voiceModelStatus: VoiceModelStatus?
    private var voiceModelPreparation: Task<Bool, Never>?

    var voice: VoiceSettings { config.voice }

    /// Prepares the model once per launch; a later call waits for that same outcome.
    func checkVoiceModel() async {
        let prepare = deps.prepareVoiceModel
        let preparation = voiceModelPreparation ?? Task { await prepare() }
        voiceModelPreparation = preparation
        voiceModelStatus = await preparation.value ? .ready : .failed
    }

    /// R4. A model that will not load outranks a missing key, since adding the key would not help.
    func voiceDisabledReason(for route: VoiceRoute) -> String? {
        if route == .local, voiceModelStatus == .failed {
            return "The voice model could not be loaded on this Mac."
        }
        let account: KeyAccount =
            switch route {
            case .local: .assemblyai
            case .speechmatics: .speechmatics
            }
        return hasKey(account) ? nil : Self.keyHint(for: account)
    }

    /// A switch that cannot be moved shows off, and its stored value is left alone.
    func isVoiceOn(_ route: VoiceRoute) -> Bool {
        voice.isEnabled(route) && voiceDisabledReason(for: route) == nil
    }

    /// The line under a switch that is on while the other provider's engine is selected.
    func voiceNote(for route: VoiceRoute) -> String? {
        guard isVoiceOn(route), activeMeetingEngine?.voiceRoute != route else { return nil }
        return switch route {
        case .local: "Used when an AssemblyAI engine is selected."
        case .speechmatics: "Used when a Speechmatics engine is selected."
        }
    }

    var voiceTuningShown: Bool { VoiceRoute.allCases.contains { isVoiceOn($0) } }

    var voiceResetOffered: Bool { voice.step != Self.balancedVoiceStep }

    /// Speechmatics sensitivity belongs to its route; every other value to the local one.
    func isVoiceFieldDimmed(_ field: VoiceSettings.Field) -> Bool {
        !isVoiceOn(field == .sensitivity ? .speechmatics : .local)
    }

    static func voiceCaption(_ voice: VoiceSettings) -> VoiceCaption {
        guard let step = voice.step else { return VoiceCaption(name: "Custom", detail: "set in Advanced") }
        let name =
            switch step {
            case ...1: "Most cautious"
            case 2...4: "Cautious"
            case balancedVoiceStep: "Balanced"
            case 6...8: "Eager"
            default: "Most eager"
            }
        let sure = voiceReadOut(.sure, of: voice)
        let suggestion = voiceReadOut(.suggestion, of: voice)
        return VoiceCaption(name: name, detail: "applies a name at \(sure), suggests from \(suggestion)")
    }

    /// A hand-set value is on no step, so the slider rests on the step nearest its sure threshold.
    static func voiceSliderStep(_ voice: VoiceSettings) -> Int {
        if let step = voice.step { return step }
        let distance = { (step: Int) in abs(voice.tuned(toStep: step).sureThreshold - voice.sureThreshold) }
        return VoiceSettings.steps.min { distance($0) < distance($1) } ?? balancedVoiceStep
    }

    static func voiceReadOut(_ field: VoiceSettings.Field, of voice: VoiceSettings) -> String {
        let value = voice.value(of: field)
        return isSeconds(field) ? "\(Int(value.rounded())) s" : String(format: "%.2f", value)
    }

    func setVoiceEnabled(_ enabled: Bool, for route: VoiceRoute) async {
        guard voiceDisabledReason(for: route) == nil else { return }
        await write { config in
            switch route {
            case .local: config.voice.localEnabled = enabled
            case .speechmatics: config.voice.speechmaticsEnabled = enabled
            }
        }
    }

    func setVoiceStep(_ step: Int) async {
        await write { $0.voice = $0.voice.tuned(toStep: step) }
    }

    /// Stored as it reads out. The whole value is validated, so a sure threshold set below the
    /// suggestion threshold takes it down too.
    func setVoice(_ value: Double, for field: VoiceSettings.Field) async {
        let rounded = Self.isSeconds(field) ? value.rounded() : (value * 100).rounded() / 100
        await write { $0.voice = $0.voice.setting(field, to: rounded) }
    }

    func resetVoiceTuning() async {
        await setVoiceStep(Self.balancedVoiceStep)
    }

    private static func isSeconds(_ field: VoiceSettings.Field) -> Bool {
        field == .minimumSpeech || field == .buffer
    }

    // MARK: - Speaker names (design v9 §3 R1–R3, R24)

    /// A switch that cannot be moved shows off and writes nothing, so its stored value returns with a key.
    var namingBlocked: Bool { !hasKey(.anthropic) }
    var namingEnabled: Bool { config.meetingNamingEnabled && !namingBlocked }
    var autoApplyLocked: Bool { !namingEnabled }
    var namingAutoApply: Bool { config.meetingNamingAutoApply && !autoApplyLocked }
    var nameAliases: [String] { config.meetingUserNameAliases }

    func setNamingEnabled(_ enabled: Bool) async {
        guard !namingBlocked else { return }
        await write { $0.meetingNamingEnabled = enabled }
    }

    func setNamingAutoApply(_ enabled: Bool) async {
        guard !autoApplyLocked else { return }
        await write { $0.meetingNamingAutoApply = enabled }
    }

    /// Appended to the stored list rather than replacing it, so a spelling That's me added meanwhile stays.
    @discardableResult
    func addNameAlias(_ alias: String) async -> Bool {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = NameFold.key(trimmed)
        guard PeopleModel.acceptsName(trimmed), key != NameFold.key(meetingUserName),
            !nameAliases.contains(where: { NameFold.key($0) == key })
        else { return false }
        await write { $0.meetingUserNameAliases.append(trimmed) }
        return true
    }

    func removeNameAlias(_ alias: String) async {
        await write { $0.meetingUserNameAliases.removeAll { $0 == alias } }
    }

    // MARK: - Appearance (R8)

    var theme: AppTheme { config.theme }

    /// Applied app-wide by `AppDelegate`'s config-change consumer.
    func setTheme(_ theme: AppTheme) async {
        await write { $0.theme = theme }
    }

    // MARK: - Overlay (design v3 §5.4)

    var overlayStyleRows: [OverlayStyleRow] { OverlayStyleCatalog.rows }
    var selectedOverlayStyle: OverlayStyle { config.overlayStyle }

    func setOverlayStyle(_ style: OverlayStyle) async {
        await write { $0.overlayStyle = style }
    }

    // MARK: - Keys (F3)

    func mask(for account: KeyAccount) -> String {
        masks[account] ?? ""
    }

    func error(for account: KeyAccount) -> String? {
        keyErrors[account]
    }

    private func hasKey(_ account: KeyAccount) -> Bool {
        !mask(for: account).isEmpty
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
        if let prefix = Self.keyPrefixes[account], !key.hasPrefix(prefix) {
            keyErrors[account] = "Invalid key — must start with '\(prefix)'."
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

    private static let keyPrefixes: [KeyAccount: String] = [.openai: "sk-", .anthropic: "sk-ant-"]

    private static func mask(of secret: String, account: KeyAccount) -> String {
        guard account == .openai else { return dotMask }
        return "sk-…\(secret.suffix(4))"
    }

    // MARK: - Hotkeys (F7)

    static func title(of binding: BindingName) -> String {
        switch binding {
        case .paste: "Record"
        case .pasteSubmit: "Record and submit"
        case .meeting: "Meeting"
        }
    }

    func display(_ binding: BindingName) -> String {
        displays[binding] ?? ""
    }

    func hotkeyError(for binding: BindingName) -> String? {
        hotkeyErrors[binding]
    }

    func beginCapture(_ binding: BindingName) {
        if capturing != nil { cancelCapture() }
        hotkeyErrors = [:]
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
    /// matcher in capture mode, so the field simply keeps waiting. A combo another
    /// binding already uses is refused and the field keeps its value (design §5.7).
    func handle(_ action: HotkeyAction) async {
        guard let binding = capturing else { return }
        switch action {
        case .captured(let combo):
            let clash = BindingName.allCases.first {
                $0 != binding && (try? HotkeyCombo.parse(stored($0))) == combo
            }
            displays[binding] = clash == nil ? combo.displayString : previousDisplay ?? ""
            capturing = nil
            previousDisplay = nil
            if let clash {
                hotkeyErrors[binding] = "Already used by \(Self.title(of: clash))"
                return
            }
            deps.hotkeys.update(binding: binding, combo: combo)
            await write { config in
                switch binding {
                case .paste: config.hotkey = combo.configString
                case .pasteSubmit: config.submitHotkey = combo.configString
                case .meeting: config.meetingHotkey = combo.configString
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
        case .meeting: config.meetingHotkey
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
