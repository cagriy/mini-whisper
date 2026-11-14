import AppKit
import SwiftUI

/// A meeting while it runs (design §5.9 *Live meeting*): the header with the title, chips, time,
/// cost, Pause and Stop; then the transcript beside the Notes pane, or the Script pane of a test call.
struct LivePage: View {
    let model: MeetingWindowModel
    let actions: MeetingActions
    @Binding var dialog: PageDialog?

    private var isPaused: Bool {
        if case .paused = model.state { true } else { false }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = model.errorMessage {
                StatusLine(error, .error)
            }
            if let hint = model.silenceHint {
                StatusLine(hint, .warning) {
                    Button("Open Privacy Settings…") {
                        NSWorkspace.shared.open(MeetingWindowModel.privacySettingsURL)
                    }
                    .buttonStyle(.pill(size: .small))
                }
            }
            HStack(spacing: 0) {
                TranscriptView(model: model, actions: actions, dialog: $dialog)
                pane
            }
        }
    }

    @ViewBuilder private var pane: some View {
        if let testCall = model.testCall {
            Group {
                if testCall.score == nil {
                    ScriptPane(model: testCall, skip: actions.skipLine)
                } else {
                    ScorePane(model: testCall) { await model.loadEarlierRuns() }
                }
            }
            .frame(width: 310)
        } else {
            NotesPane(model: model, actions: actions).frame(width: 280)
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.s5) {
            TitleField(model: model, style: .titleCompact, retitle: actions.retitle)
                .frame(maxWidth: 360, alignment: .leading)
            if model.isTest {
                TestTag()
            } else {
                Chip(MeetingWindowModel.title(of: model.mode))
            }
            if isPaused {
                Chip("Paused", .inactive)
            } else {
                Chip(model.captureChip, model.state == .recording ? .active : .inactive)
            }
            if let connection = model.connectionChip {
                Chip(connection, .warning)
            }
            Spacer(minLength: 0)
            Text(model.elapsedText)
                .textStyle(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.Colors.text)
            Text("\(model.costText) so far")
                .textStyle(.body)
                .monospacedDigit()
                .foregroundStyle(DS.Colors.textSecondary)
            Button(action: actions.pauseOrResume) {
                Label(model.pauseTitle, systemImage: isPaused ? "play" : "pause")
            }
            .buttonStyle(.pill(size: .small))
            .disabled(!model.canPause)
            .help(model.pauseHelp ?? "")
            Button(action: actions.stop) {
                HStack(spacing: DS.Space.s3) {
                    RoundedRectangle(cornerRadius: 2).fill(DS.Colors.recording).frame(width: 9, height: 9)
                    Text("Stop")
                }
            }
            .buttonStyle(.pill(size: .small))
            .disabled(!model.canStop)
        }
        .lineLimit(1)
        .padding(.horizontal, 20)
        .padding(.top, DS.Space.s7)
        .padding(.bottom, DS.Space.s7 + DS.Size.hairline)
        .hairline(.bottom)
    }
}
