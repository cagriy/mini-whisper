import MWConfig
import SwiftUI

/// R20's Meetings section, as the overview mockup lays it out: engine, recording, speaker names,
/// summary prompt, storage, then the command-line tool and the agents.
struct MeetingsSection: View {
    @Bindable var model: SettingsModel

    @State private var userName = ""
    @FocusState private var editingName: Bool
    @State private var aliasDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            engines
            recording
            speakerNames
            summaryPrompt
            storage
            agents
        }
        .onAppear {
            userName = model.meetingUserName
            model.loadSummaryPrompt()
        }
        .task { await model.refreshMeetings() }
        .task { await model.checkVoiceModel() }
        .onDisappear(perform: commitName)
        .onChange(of: editingName) { _, editing in
            if !editing { commitName() }
        }
    }

    /// Each provider's engines with its voice switch under them; the tuning closes the card while a
    /// switch is on.
    private var engines: some View {
        Card("Engine") {
            SettingRow.full {
                ForEach(Array(Self.routes.enumerated()), id: \.element) { index, route in
                    if index > 0 {
                        Rectangle()
                            .fill(DS.Colors.line)
                            .frame(height: DS.Size.hairline)
                            .padding(.vertical, DS.Space.s4)
                    }
                    ForEach(model.meetingEngineRows.filter { $0.engine.voiceRoute == route }) { row in
                        engineRow(row)
                    }
                    voiceSwitch(route)
                }
            }
            if model.voiceTuningShown {
                SettingRow.full { VoiceTuning(model: model) }
            }
            SettingRow.full {
                SettingsFootnote(
                    "Meetings are English only. The second AssemblyAI figure is its speaker-labels add-on."
                        + " These list prices drive a live meeting's running cost and the Today/Month totals."
                )
            }
        }
    }

    /// The routes in the order of their engines.
    private static let routes: [VoiceRoute] = MeetingEngine.allCases.reduce(into: []) { routes, engine in
        if !routes.contains(engine.voiceRoute) { routes.append(engine.voiceRoute) }
    }

    /// An inset box under the route's engine rows. The disclosure always shows; a reason the switch
    /// cannot be moved, or when it applies, reads under it.
    private func voiceSwitch(_ route: VoiceRoute) -> some View {
        let title =
            switch route {
            case .local: "Remember voices on this Mac"
            case .speechmatics: "Remember voices with Speechmatics"
            }
        let disclosure =
            switch route {
            case .local:
                "Learns the voice of each speaker you name and names them in later meetings. Keeps a voiceprint"
                    + " per person, never audio, in ~/.config/mini-whisper/voices.json and in each meeting's"
                    + " folder. Nothing leaves this Mac."
            case .speechmatics:
                "Speechmatics returns a voice identifier for each speaker you name, and later meetings send those"
                    + " identifiers back so it can name them. Kept in ~/.config/mini-whisper/voices.json, never"
                    + " audio. Names are not sent."
            }
        let reason = model.voiceDisabledReason(for: route)
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).textStyle(.body.weight(.medium)).foregroundStyle(DS.Colors.text)
                Group {
                    Text(disclosure).foregroundStyle(DS.Colors.textSecondary)
                    if let reason {
                        Text(reason).foregroundStyle(DS.Colors.warn)
                    } else if let note = model.voiceNote(for: route) {
                        Text(note).foregroundStyle(DS.Colors.textTertiary)
                    }
                }
                .textStyle(.meta)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(
                title,
                isOn: settingsBinding(model.isVoiceOn(route)) { await model.setVoiceEnabled($0, for: route) }
            )
            .toggleStyle(.ds)
            .disabled(reason != nil)
        }
        .padding(.vertical, DS.Space.s5 + DS.Size.hairline)
        .padding(.horizontal, DS.Space.s6 + DS.Size.hairline)
        .background(RoundedRectangle(cornerRadius: DS.Radius.row).fill(DS.Colors.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.row).strokeBorder(DS.Colors.line))
        // In line with the radio titles: past the 16 pt ring and its gap.
        .padding(.leading, 16 + DS.Space.s5)
        .padding(.top, DS.Space.s2)
        .padding(.bottom, DS.Space.s3)
    }

    private func engineRow(_ row: SettingsModel.MeetingEngineRow) -> some View {
        RadioRow(
            row.title,
            detail: row.disabledReason.map { .warning($0) } ?? .plain(row.subtitle),
            selected: model.activeMeetingEngine == row.engine,
            select: { Task { await model.selectMeetingEngine(row.engine) } }
        ) {
            Text(row.price)
                .textStyle(.body)
                .monospacedDigit()
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .disabled(!row.isEnabled)
    }

    private var recording: some View {
        Card("Recording") {
            SettingRow(
                "Your name",
                description: "Labels your microphone in remote calls and in exports. Starts as your macOS account name."
            ) {
                TextField("Your name", text: $userName, prompt: Text(""))
                    .labelsHidden()
                    .fieldPlaceholder("Your name", shown: userName.isEmpty)
                    .dsField()
                    .focused($editingName)
                    .onSubmit(commitName)
                    .frame(width: 220)
            }
            SettingRow(
                "Keep meeting audio",
                description: "Saves the audio as AAC beside the transcript, about 14 MB per hour. Off keeps transcripts"
                    + " only; audio of past meetings is deleted per meeting from the Meetings page."
            ) {
                Toggle(
                    "Keep meeting audio",
                    isOn: settingsBinding(model.config.meetingKeepAudio) { await model.setMeetingKeepAudio($0) }
                )
                .toggleStyle(.ds)
            }
            SettingRow(
                "Stop after silence",
                description: SettingsModel.silenceStopDescription(model.config.meetingSilenceStopSeconds)
            ) {
                SegmentedPill(
                    selection: settingsBinding(model.config.meetingSilenceStopSeconds) {
                        await model.setMeetingSilenceStop($0)
                    },
                    options: [(0, "Off"), (60, "1 min"), (120, "2 min"), (300, "5 min")]
                )
            }
            SettingRow(
                "System Audio Recording",
                description: "macOS asks for this permission at the first remote meeting. If a remote call's transcript"
                    + " shows only your side, allow Mini Whisper under Privacy & Security → Screen & System"
                    + " Audio Recording."
            ) {
                Button("Open Privacy Settings…") { NSWorkspace.shared.open(SettingsModel.privacySettingsURL) }
                    .buttonStyle(.pill(size: .small))
            }
        }
    }

    private var summaryPrompt: some View {
        Card("Summary") {
            SettingRow.full("Summary prompt", spacing: DS.Space.s4) {
                PromptTextEditor(title: "Summary prompt", text: $model.summaryPromptDraft)
                HStack(spacing: DS.Space.s5) {
                    Button("Save Prompt", action: model.saveSummaryPrompt)
                    Button("Open in Editor") {
                        model.saveSummaryPrompt()
                        NSWorkspace.shared.open(model.summaryPromptURL)
                    }
                    Button("Restore Default", action: model.restoreDefaultSummaryPrompt)
                }
                .buttonStyle(.pill(size: .small))
                if let error = model.promptError {
                    ErrorLine(error)
                }
                SettingsFootnote("Claude Sonnet 5.5 writes the summary when a meeting stops.")
                anthropicKeyHint
            }
        }
    }

    @ViewBuilder private var anthropicKeyHint: some View {
        if let hint = model.summaryKeyHint {
            Text(hint).textStyle(.meta).foregroundStyle(DS.Colors.warn)
        }
    }

    private var speakerNames: some View {
        Card("Speaker names") {
            SettingRow(
                "Suggest names from the conversation",
                description: "During a meeting, Claude Haiku 5.5 suggests a name for a speaker when someone says it,"
                    + " with the line it came from. The transcript so far, your name and the names in People go to"
                    + " Anthropic several times a meeting. About 3 cents a meeting, on the meeting's cost line."
            ) {
                Toggle(
                    "Suggest names from the conversation",
                    isOn: settingsBinding(model.namingEnabled) { await model.setNamingEnabled($0) }
                )
                .toggleStyle(.ds)
                .disabled(model.namingBlocked)
            }
            SettingRow(
                "Apply self-introductions without asking",
                description: "A speaker who says their own name, as in “I’m Kate”, is named straight away; “Not Kate”"
                    + " undoes it. Off, it is a suggestion like any other."
            ) {
                Toggle(
                    "Apply self-introductions without asking",
                    isOn: settingsBinding(model.namingAutoApply) { await model.setNamingAutoApply($0) }
                )
                .toggleStyle(.ds)
                .disabled(model.autoApplyLocked)
            }
            .opacity(model.autoApplyLocked ? 0.5 : 1)
            SettingRow.full("Your name, as misheard") {
                (Text("Spellings treated as your name and never suggested for another speaker. ")
                    + Text("That's me").fontWeight(.semibold).foregroundStyle(DS.Colors.text)
                    + Text(" on a suggestion adds one."))
                    .textStyle(.meta)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                aliasList.padding(.top, DS.Space.s4)
            }
            SettingRow.full {
                SettingsFootnote(
                    "Names you or your voices settings already gave are never replaced. Suggest names on a stopped"
                        + " meeting works with this off."
                )
                anthropicKeyHint
            }
        }
    }

    private var aliasList: some View {
        let hairline = Rectangle().fill(DS.Colors.line).frame(height: DS.Size.hairline)
        return VStack(alignment: .leading, spacing: 0) {
            if model.nameAliases.isEmpty {
                Text("None yet.")
                    .textStyle(.meta)
                    .foregroundStyle(DS.Colors.textTertiary)
                    .spellingRow()
            } else {
                ForEach(Array(model.nameAliases.enumerated()), id: \.element) { index, alias in
                    if index > 0 { hairline }
                    AliasRow(alias: alias) { Task { await model.removeNameAlias(alias) } }
                }
            }
            hairline
            TextField("Add a spelling", text: $aliasDraft, prompt: Text(""))
                .labelsHidden()
                .fieldPlaceholder("Add a spelling", shown: aliasDraft.isEmpty)
                .dsField()
                .onSubmit(commitAlias)
                .frame(width: 180)
                .spellingRow()
        }
        .padding(DS.Size.hairline)
        .background(RoundedRectangle(cornerRadius: DS.Radius.row).fill(DS.Colors.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.row).strokeBorder(DS.Colors.line))
    }

    private func commitAlias() {
        let alias = aliasDraft
        aliasDraft = ""
        Task { await model.addNameAlias(alias) }
    }

    private var storage: some View {
        Card("Storage") {
            SettingRow(
                model.storageText,
                description: "Meetings live in ~/.config/mini-whisper/meetings and are never deleted automatically."
            ) {
                Button("Show in Finder", action: model.showMeetingsFolder)
                    .buttonStyle(.pill(size: .small))
            }
        }
    }

    private var agents: some View {
        Card("Command line and agents") {
            SettingRow(
                "Command-line tool",
                description: "Installs \(CommandLineToolInstaller.path), a small launcher for this app; macOS asks for an"
                    + " administrator password if that folder needs one. Then mini-whisper meetings list |"
                    + " transcript <id> | summary <id> | search <text> works in any terminal."
            ) {
                HStack(spacing: DS.Space.s5) {
                    Text(model.toolStatus)
                        .textStyle(.body)
                        .foregroundStyle(DS.Colors.textSecondary)
                    Button("Install…", action: model.installTool)
                        .buttonStyle(.pill(size: .small))
                }
            }
            command(
                "Claude Code",
                model.claudeCodeCommand,
                copy: model.copyClaudeCodeCommand,
                footnote: "Registers a read-only MCP server with four tools: list_meetings, get_transcript, get_summary,"
                    + " search_meetings. Nothing in the app can be changed through it."
            )
            command(
                "ChatGPT",
                model.chatGPTCommand,
                copy: model.copyChatGPTCommand,
                footnote: "In the ChatGPT app for Mac: Settings → MCP servers → Add server. Name it mini-whisper, choose"
                    + " STDIO, paste this as the command and add the argument mcp. Save, then Restart. ChatGPT"
                    + " on the web cannot reach servers on this Mac."
            )
        }
    }

    /// A command to copy: its text in the monospaced style beside Copy, the footnote under both.
    private func command(_ title: String, _ text: String, copy: @escaping () -> Void, footnote: String) -> some View {
        SettingRow.full(title, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(text)
                    .textStyle(.mono)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy", action: copy)
                    .buttonStyle(.pill(size: .small))
            }
            SettingsFootnote(footnote)
        }
    }

    /// Writes only a changed name, so leaving the field untouched never stores the account name.
    private func commitName() {
        guard userName != model.meetingUserName else { return }
        Task {
            await model.setMeetingUserName(userName)
            userName = model.meetingUserName
        }
    }
}

/// A misheard spelling of the user's name, with Remove in reserved space on hover or focus.
private struct AliasRow: View {
    let alias: String
    let remove: () -> Void

    @State private var hovered = false
    @FocusState private var focused: Bool

    private var active: Bool { hovered || focused }

    var body: some View {
        HStack(spacing: DS.Space.s5) {
            Text(alias)
                .textStyle(.body)
                .foregroundStyle(DS.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Kept in the layout when hidden, so hovering never moves the row.
            Button("Remove", action: remove)
                .buttonStyle(.pill(.quietAction, size: .small))
                .focused($focused)
                .opacity(active ? 1 : 0)
                .allowsHitTesting(active)
                .accessibilityLabel("Remove \(alias)")
        }
        .spellingRow()
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

extension View {
    fileprivate func spellingRow() -> some View {
        frame(minHeight: DS.Size.controlSmall)
            .padding(.vertical, DS.Space.s2)
            .padding(.leading, DS.Space.s6)
            .padding(.trailing, DS.Space.s3)
    }
}

/// The Cautious–Eager slider with its caption, and the six values under Advanced. As Sound › Volume's,
/// the sliders follow a drag and write once it ends; the caption and read-outs follow the drag too.
private struct VoiceTuning: View {
    let model: SettingsModel

    /// The tuning a drag under way would write.
    @State private var draft: VoiceSettings?
    @State private var advancedOpen = false

    private static let steps = Double(VoiceSettings.steps.lowerBound)...Double(VoiceSettings.steps.upperBound)

    var body: some View {
        let shown = draft ?? model.voice
        let caption = SettingsModel.voiceCaption(shown)
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s6) {
                    Text("How readily names are applied")
                        .textStyle(.body.weight(.medium))
                        .foregroundStyle(DS.Colors.text)
                    Spacer(minLength: 0)
                    (Text(caption.name).fontWeight(.semibold).foregroundStyle(DS.Colors.text)
                        + Text(" · \(caption.detail)"))
                        .textStyle(.meta)
                        .monospacedDigit()
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                HStack(spacing: DS.Space.s5) {
                    Text("Cautious")
                    Slider(
                        value: Binding(
                            get: { Double(SettingsModel.voiceSliderStep(shown)) },
                            set: { draft = model.voice.tuned(toStep: Int($0.rounded())) }
                        ),
                        in: Self.steps,
                        step: 1
                    ) { editing in
                        guard !editing, let step = draft?.step else { return }
                        commit { await model.setVoiceStep(step) }
                    }
                    // The stock thumb cannot be drawn hollow, so a hand-set value shows an unfilled track.
                    .tint(shown.step == nil ? DS.Colors.line : DS.Colors.accent)
                    .accessibilityLabel("Cautious to Eager")
                    Text("Eager")
                }
                .textStyle(.meta)
                .foregroundStyle(DS.Colors.textSecondary)
            }
            DisclosureGroup(isExpanded: $advancedOpen) {
                VStack(alignment: .leading, spacing: DS.Space.s5) {
                    ForEach(VoiceSettings.Field.allCases, id: \.self) { field in
                        advancedRow(field, shown: shown)
                    }
                    if model.voiceResetOffered {
                        Button("Reset to Balanced") { Task { await model.resetVoiceTuning() } }
                            .buttonStyle(.plain)
                            .textStyle(.meta.weight(.medium))
                            .foregroundStyle(DS.Colors.accent)
                    }
                }
                .padding(.top, DS.Space.s5)
            } label: {
                // The stock label does not toggle on macOS; the word should, as the arrow does.
                Button("Advanced") { advancedOpen.toggle() }
                    .buttonStyle(.plain)
                    .textStyle(.meta.weight(.medium))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
        }
    }

    private func advancedRow(_ field: VoiceSettings.Field, shown: VoiceSettings) -> some View {
        let (title, description) = Self.text(of: field)
        return HStack(spacing: DS.Space.s7) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).textStyle(.body.weight(.medium)).foregroundStyle(DS.Colors.text)
                Text(description)
                    .textStyle(.meta)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Slider(
                value: Binding(
                    get: { shown.value(of: field) },
                    set: { draft = (draft ?? model.voice).setting(field, to: $0) }
                ),
                in: VoiceSettings.range(of: field)
            ) { editing in
                guard !editing, let value = draft?.value(of: field) else { return }
                commit { await model.setVoice(value, for: field) }
            }
            .tint(DS.Colors.accent)
            .frame(width: 200)
            .accessibilityLabel(title)
            Text(SettingsModel.voiceReadOut(field, of: shown))
                .textStyle(.body)
                .monospacedDigit()
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(width: 52, alignment: .trailing)
        }
        .opacity(model.isVoiceFieldDimmed(field) ? 0.5 : 1)
    }

    /// Writes, then shows the stored tuning again unless another drag has begun meanwhile.
    private func commit(_ write: @escaping @MainActor () async -> Void) {
        let committed = draft
        Task {
            await write()
            if draft == committed { draft = nil }
        }
    }

    private static func text(of field: VoiceSettings.Field) -> (title: String, description: String) {
        switch field {
        case .sure: ("Sure match", "A score at or above this applies the name.")
        case .suggestion: ("Suggestion", "From this score up, the name is offered.")
        case .margin: ("Margin", "How far ahead of the next-best person a match must be.")
        case .minimumSpeech: ("Minimum speech", "Speech heard from a voice before the first check.")
        case .buffer: ("Audio buffer", "Recent audio kept in memory for matching. Not set by the slider.")
        case .sensitivity: ("Speechmatics sensitivity", "Higher keeps unknown voices apart from remembered ones.")
        }
    }
}
