import SwiftUI

/// R20's Meetings section, as the overview mockup lays it out: engine, recording, summary
/// prompt, storage, then the command-line tool and the agents.
struct MeetingsSection: View {
    @Bindable var model: SettingsModel

    @State private var userName = ""
    @FocusState private var editingName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            engines
            recording
            summaryPrompt
            storage
            agents
        }
        .onAppear {
            userName = model.meetingUserName
            model.loadSummaryPrompt()
        }
        .task { await model.refreshMeetings() }
        .onDisappear(perform: commitName)
        .onChange(of: editingName) { _, editing in
            if !editing { commitName() }
        }
    }

    private var engines: some View {
        Card("Engine") {
            SettingRow.full(spacing: DS.Space.s2) {
                VStack(spacing: 0) {
                    ForEach(model.meetingEngineRows) { row in
                        engineRow(row)
                    }
                }
                SettingsFootnote(
                    "Meetings are English only. The second AssemblyAI figure is its speaker-labels add-on."
                        + " These list prices drive the running cost in the meeting window and the Today/Month totals."
                )
            }
        }
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
                if let hint = model.summaryKeyHint {
                    Text(hint).textStyle(.meta).foregroundStyle(DS.Colors.warn)
                }
            }
        }
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
