import SwiftUI

/// The Meetings window of design §3 R16, matching the accepted mockup
/// `mockup-v4-meetings-list.html`: search, day-grouped rows with hover actions, the empty
/// state and a footer.
struct MeetingsListView: View {
    @Bindable var model: MeetingsListModel

    @State private var hovered: UUID?
    @State private var renaming: UUID?
    @State private var renameDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            if let message = model.emptyState {
                EmptyMeetings(message: message, startMeeting: model.startMeeting)
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: 680, height: 480)
        .confirmationDialog(
            model.pendingDeletion?.prompt ?? "",
            isPresented: Binding(get: { model.pendingDeletion != nil }, set: { if !$0 { model.cancelDeletion() } })
        ) {
            Button(model.pendingDeletion?.confirmTitle ?? "Delete", role: .destructive) {
                Task { await model.confirmDeletion() }
            }
            Button("Cancel", role: .cancel) { model.cancelDeletion() }
        } message: {
            Text(model.pendingDeletion?.detail ?? "")
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search meetings", text: $model.query).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor)))
            .frame(width: 220)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var list: some View {
        List {
            ForEach(model.days) { day in
                Section {
                    ForEach(day.rows) { row in
                        rowView(row)
                            .onHover { inside in
                                hovered = inside ? row.id : (hovered == row.id ? nil : hovered)
                            }
                    }
                } header: {
                    Text(day.title).font(.system(size: 11)).textCase(.uppercase).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if model.days.isEmpty {
                Text("No matches").foregroundStyle(.secondary)
            }
        }
    }

    private func rowView(_ row: MeetingsListModel.Row) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(row.mode == .remote ? AppGlyph.palette[0] : AppGlyph.palette[5])
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: row.mode == .remote ? "display" : "person.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                if renaming == row.id {
                    TextField("Title", text: $renameDraft)
                        .onSubmit { commitRename(row) }
                        .onExitCommand { renaming = nil }
                } else {
                    HStack(spacing: 8) {
                        Text(row.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if row.isTest { TestTag() }
                    }
                }
                if row.snippets.isEmpty {
                    Text(row.excerpt)
                        .font(.system(size: 12.5))
                        .italic(row.excerptIsTranscript)
                        .foregroundStyle(row.excerptIsTranscript ? .secondary : .primary)
                        .lineLimit(2)
                } else {
                    ForEach(Array(row.snippets.enumerated()), id: \.offset) { _, snippet in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(snippet.label).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                            Text(snippet.text).font(.system(size: 12)).lineLimit(2)
                        }
                    }
                }
                Text(row.meta).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Kept in the layout when hidden, so hovering never rewraps the text.
            actions(row)
                .opacity(hovered == row.id ? 1 : 0)
                .allowsHitTesting(hovered == row.id)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { Task { await model.open(row) } }
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
        HStack(spacing: 6) {
            Button("Open") { Task { await model.open(row) } }
            Menu("Export") {
                ForEach(model.exportItems(for: row), id: \.title) { item in
                    if item.action == .deleteAudio { Divider() }
                    Button(item.title) { model.perform(item, on: row) }
                        .disabled(item.action == .deleteAudio && !model.canDelete(row))
                }
            }
            .fixedSize()
            Button { model.requestDelete(row) } label: { Text("Delete").foregroundStyle(Color.red) }
                .disabled(!model.canDelete(row))
                .help(model.canDelete(row) ? "" : "Close the meeting's window to delete it")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func commitRename(_ row: MeetingsListModel.Row) {
        renaming = nil
        let title = renameDraft
        Task { await model.rename(row, to: title) }
    }

    private var footer: some View {
        HStack {
            Text(model.footer).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button("Show in Finder", action: model.showInFinder)
            Button("Start Meeting…", action: model.startMeeting)
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// Mockup State 3: before the first meeting.
private struct EmptyMeetings: View {
    let message: String
    let startMeeting: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .quaternaryLabelColor))
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "person.2.wave.2").font(.title2).foregroundStyle(.secondary))
            Text("No meetings yet").font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Start Meeting…", action: startMeeting).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}
