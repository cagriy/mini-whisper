import SwiftUI

/// A stopped meeting (design §5.9 *Finished meeting*): the top bar with the back pill, Copy
/// summary, Regenerate and Export ▾; the title, chips and the Summary · Transcript · Notes switch.
/// A test call's transcript shares the page with its Score pane.
struct FinishedPage: View {
    @Bindable var model: MeetingWindowModel
    let actions: MeetingActions
    let backLabel: String
    @Binding var dialog: PageDialog?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if model.isTest, model.selectedTab == .transcript {
                head
                    .padding(EdgeInsets(top: DS.Space.s2, leading: 32, bottom: DS.Space.s7, trailing: 32))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    TranscriptView(model: model, actions: actions, dialog: $dialog)
                    scorePane.frame(width: 310)
                }
                .hairline(.top)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s8) {
                        head
                        tab
                    }
                    .padding(EdgeInsets(top: DS.Space.s6, leading: 32, bottom: 56, trailing: 32))
                    .frame(maxWidth: DS.Size.pageColumn, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var topBar: some View {
        TopBar {
            Button(action: actions.back) {
                Label(backLabel, systemImage: "chevron.left")
            }
            .buttonStyle(.pill(size: .small))
            .keyboardShortcut("[")
            Spacer(minLength: 0)
            Button(model.justCopied ? "Copied" : "Copy summary", action: actions.copySummary)
                .buttonStyle(.pill(size: .small))
                .disabled(!model.canCopySummary)
            Button("Regenerate", action: confirmRegenerate)
                .buttonStyle(.pill(size: .small))
                .disabled(!model.canRegenerate)
            PillMenu(title: "Export") {
                [
                    PillMenu.Item(title: "Export transcript…") { actions.export(.transcript) },
                    PillMenu.Item(title: "Export summary…") { actions.export(.summary) },
                    PillMenu.Item(title: "Export both…") { actions.export(.both) },
                ]
            }
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s5) {
                TitleField(model: model, style: .display, lineLimit: nil, retitle: actions.retitle)
                if model.isTest { TestTag() }
            }
            FlowLayout {
                ForEach(Array(model.chips.enumerated()), id: \.offset) { _, chip in Chip(chip) }
            }
            SegmentedPill(selection: $model.selectedTab, options: [
                (.summary, "Summary"), (.transcript, "Transcript"), (.notes, model.notesTabTitle),
            ])
        }
    }

    @ViewBuilder private var tab: some View {
        switch model.selectedTab {
        case .summary:
            if let panel = model.summaryPanel {
                SummaryView(panel: panel, summarise: actions.summarise)
            }
        case .transcript:
            TranscriptView(model: model, actions: actions, dialog: $dialog, scrolls: false)
        case .notes:
            NotesList(notes: model.notes)
        }
    }

    /// The score once Stop has read or computed it; until then the script.
    @ViewBuilder private var scorePane: some View {
        if let testCall = model.testCall {
            if testCall.score == nil {
                ScriptPane(model: testCall, skip: actions.skipLine)
            } else {
                ScorePane(model: testCall) { await model.loadEarlierRuns() }
            }
        }
    }

    private func confirmRegenerate() {
        guard let prompt = model.regeneratePrompt else { return }
        dialog = PageDialog(
            title: "Regenerate the summary?", message: prompt, confirmTitle: "Regenerate", confirm: actions.regenerate
        )
    }
}
