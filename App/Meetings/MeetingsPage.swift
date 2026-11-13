import SwiftUI

/// The Meetings page (design §5.9, R18): the count line with Show in Finder, then the stored
/// meetings by day, or the empty state before the first.
struct MeetingsPage: View {
    let model: MeetingsListModel

    @State private var renaming: UUID?
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        PageColumn("Meetings") {
            if let message = model.emptyState {
                if let error = model.errorMessage { StatusLine(error, .warning) }
                EmptyMeetings(message: message, startMeeting: model.startMeeting)
            } else {
                HStack(spacing: DS.Space.s5) {
                    Text(model.footer)
                    Button("Show in Finder", action: model.showInFinder)
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.Colors.accent)
                }
                .textStyle(.body)
                .foregroundStyle(DS.Colors.textSecondary)
                .padding(.top, -DS.Space.s5)
                if let error = model.errorMessage { StatusLine(error, .warning) }
                LazyVStack(alignment: .leading, spacing: DS.Space.s1) {
                    ForEach(model.days) { day in
                        DayHeader(day.title)
                        ForEach(day.rows) { row in rowView(row) }
                    }
                }
            }
        }
    }

    private func rowView(_ row: MeetingsListModel.Row) -> some View {
        ListRow(time: row.time, open: { Task { await model.open(row) } }) {
            Tile(mode: row.mode)
        } content: { active in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DS.Space.s4) {
                    if renaming == row.id {
                        TextField("Title", text: $renameDraft)
                            .textFieldStyle(.plain)
                            .focused($renameFocused)
                            .onSubmit { commitRename(row) }
                            .onExitCommand { renaming = nil }
                            .onAppear { renameFocused = true }
                    } else {
                        Text(row.title).lineLimit(1)
                    }
                    if row.isTest { Chip("TEST", .test) }
                }
                .textStyle(.rowTitle)
                .foregroundStyle(DS.Colors.text)
                if !row.subLine.isEmpty {
                    Text(row.subLine)
                        .textStyle(.body)
                        .italic(row.subLineIsTranscript)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: DS.Space.s4) {
                    Text(row.meta)
                        .textStyle(.meta)
                        .monospacedDigit()
                        .foregroundStyle(DS.Colors.textTertiary)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    // Kept in the layout when hidden, so hovering never rewraps the row.
                    actions(row)
                        .fixedSize()
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
                }
                .frame(minHeight: DS.Size.controlSmall)
            }
        }
        .contextMenu {
            Button("Open") { Task { await model.open(row) } }
            Button("Rename…") {
                renameDraft = row.title
                renaming = row.id
            }
            Divider()
            Button("Delete…") { model.requestDelete(row) }.disabled(!model.canDelete(row))
        }
    }

    private func actions(_ row: MeetingsListModel.Row) -> some View {
        HStack(spacing: DS.Space.s3) {
            Button("Open") { Task { await model.open(row) } }
                .buttonStyle(.pill(size: .small))
            PillMenu(title: "Export") {
                model.exportItems(for: row).map { item in
                    let deletesAudio = item.action == .deleteAudio
                    return PillMenu.Item(
                        title: item.title,
                        enabled: !deletesAudio || model.canDelete(row),
                        separated: deletesAudio
                    ) { model.perform(item, on: row) }
                }
            }
            Button("Delete") { model.requestDelete(row) }
                .buttonStyle(.pill(size: .small, tint: DS.Colors.recording))
                .disabled(!model.canDelete(row))
                .help(model.deleteHelp(row) ?? "")
        }
    }

    private func commitRename(_ row: MeetingsListModel.Row) {
        renaming = nil
        let title = renameDraft
        Task { await model.rename(row, to: title) }
    }
}

/// Before the first meeting: the mark, the explanation naming the hotkey, and Start Meeting.
private struct EmptyMeetings: View {
    let message: String
    let startMeeting: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.s5) {
            CloudPulseMark()
                .stroke(DS.Colors.accent, style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                .frame(width: 72, height: 48)
                .accessibilityHidden(true)
            Text("No meetings yet")
                .textStyle(.title)
                .foregroundStyle(DS.Colors.text)
            Text(message)
                .textStyle(.body)
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: startMeeting) { Label("Start Meeting", systemImage: "waveform") }
                .buttonStyle(.pill(.primary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s10)
    }
}
