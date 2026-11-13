import SwiftUI

/// R20's one Meetings pane, as the accepted mockup `mockup-v4-settings-one-pane.html` lays it
/// out: engine, name, audio and permission, summary prompt, storage, then the command-line tool
/// and Claude Code under their own heading.
struct MeetingsSection: View {
    @Bindable var model: SettingsModel

    @State private var userName = ""
    @FocusState private var editingName: Bool

    var body: some View {
        SettingsPane(title: "Meetings") {
            engines
            Divider()
            recording
            Divider()
            summaryPrompt
            Divider()
            storage
            Text("Command line and agents").font(.headline).padding(.top, 6)
            agents
        }
        .onAppear {
            userName = model.meetingUserName
            model.loadSummaryPrompt()
        }
        .task { await model.refreshMeetings() }
        .onDisappear(perform: commitName)
    }

    private var engines: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Engine").font(.callout.weight(.medium))
            ForEach(model.meetingEngineRows) { row in
                engineRow(row)
            }
            SettingsFootnote(
                "Meetings are English only. The second AssemblyAI figure is its speaker-labels add-on."
                    + " These list prices drive the running cost in the meeting window and the Today/Month totals."
            )
        }
    }

    private func engineRow(_ row: SettingsModel.MeetingEngineRow) -> some View {
        Button {
            Task { await model.selectMeetingEngine(row.engine) }
        } label: {
            let isSelected = model.activeMeetingEngine == row.engine
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                    if let reason = row.disabledReason {
                        Text(reason).font(.caption).foregroundStyle(.orange)
                    } else {
                        Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Text(row.price).monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!row.isEnabled)
        .opacity(row.isEnabled ? 1 : 0.55)
    }

    private var recording: some View {
        VStack(alignment: .leading, spacing: 8) {
            labelled("Your name") {
                TextField("Your name", text: $userName)
                    .labelsHidden()
                    .focused($editingName)
                    .onSubmit(commitName)
                    .frame(width: 220)
            }
            SettingsFootnote(
                "Labels your microphone in remote calls and in exports. Starts as your macOS account name."
            )
            Toggle(
                "Keep meeting audio",
                isOn: settingsBinding(model.config.meetingKeepAudio) { await model.setMeetingKeepAudio($0) }
            )
            SettingsFootnote(
                "Saves the audio as AAC beside the transcript, about 14 MB per hour. Off keeps transcripts"
                    + " only; audio of past meetings is deleted per meeting from the Meetings window."
            )
            labelled("System Audio Recording") {
                Button("Open Privacy Settings…") { NSWorkspace.shared.open(SettingsModel.privacySettingsURL) }
            }
            SettingsFootnote(
                "macOS asks for this permission at the first remote meeting. If a remote call's transcript"
                    + " shows only your side, allow Mini Whisper under Privacy & Security → Screen & System"
                    + " Audio Recording."
            )
        }
        .onChange(of: editingName) { _, editing in
            if !editing { commitName() }
        }
    }

    private var summaryPrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            PromptTextEditor(title: "Summary prompt", text: $model.summaryPromptDraft)
            HStack {
                Button("Save Prompt", action: model.saveSummaryPrompt)
                Button("Open in Editor") {
                    model.saveSummaryPrompt()
                    NSWorkspace.shared.open(model.summaryPromptURL)
                }
                Button("Restore Default", action: model.restoreDefaultSummaryPrompt)
            }
            .controlSize(.small)
            if let error = model.promptError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            SettingsFootnote("Claude Sonnet 5.5 writes the summary when a meeting stops.")
            if let hint = model.summaryKeyHint {
                Text(hint).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 6) {
            labelled("Storage") {
                Text(model.storageText).foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder", action: model.showMeetingsFolder)
                Button("Open Meetings…", action: model.openMeetings)
            }
            SettingsFootnote("Meetings live in ~/.config/mini-whisper/meetings and are never deleted automatically.")
        }
    }

    private var agents: some View {
        VStack(alignment: .leading, spacing: 8) {
            labelled("Command-line tool") {
                Text(model.toolStatus).foregroundStyle(.secondary)
                Spacer()
                Button("Install…", action: model.installTool)
            }
            SettingsFootnote(
                "Installs \(CommandLineToolInstaller.path), a small launcher for this app; macOS asks for an"
                    + " administrator password if that folder needs one. Then mini-whisper meetings list |"
                    + " transcript <id> | summary <id> | search <text> works in any terminal."
            )
            labelled("Claude Code") {
                Text(model.claudeCodeCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Copy", action: model.copyClaudeCodeCommand)
            }
            SettingsFootnote(
                "Registers a read-only MCP server with four tools: list_meetings, get_transcript, get_summary,"
                    + " search_meetings. Nothing in the app can be changed through it."
            )
            labelled("ChatGPT") {
                Text(model.chatGPTCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Copy", action: model.copyChatGPTCommand)
            }
            SettingsFootnote(
                "In the ChatGPT app for Mac: Settings → MCP servers → Add server. Name it mini-whisper, choose"
                    + " STDIO, paste this as the command and add the argument mcp. Save, then Restart. ChatGPT"
                    + " on the web cannot reach servers on this Mac."
            )
        }
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).frame(width: 160, alignment: .leading)
            content()
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
