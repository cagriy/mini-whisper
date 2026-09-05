import SwiftUI

/// The History window of design §5.4, matching the accepted mockup
/// `mockup-v1-history-list.html`: search, a day-grouped list of two-line rows with
/// hover actions, and a footer carrying the retention line and `Clear History…`.
struct HistoryView: View {
    @Bindable var model: HistoryListModel

    @State private var selection: String?
    @State private var hovered: String?
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 680, height: 480)
    }

    private var header: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search dictations", text: $model.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor))
            )
            .frame(width: 220)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onChange(of: model.query) {
            Task { await model.reload() }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(model.days) { day in
                Section {
                    ForEach(day.rows) { row in
                        HistoryRow(
                            row: row,
                            showsActions: selection == row.id || hovered == row.id,
                            pasteTitle: model.pasteTitle,
                            canPaste: model.canPaste,
                            onPaste: { Task { await model.paste(row) } },
                            onCorrect: { model.correct(row) },
                            onCopy: { model.copy(row) },
                            onDelete: { Task { await model.delete(row) } }
                        )
                        .tag(row.id)
                        .onHover { inside in
                            hovered = inside ? row.id : (hovered == row.id ? nil : hovered)
                        }
                    }
                } header: {
                    Text(day.title)
                        .font(.system(size: 11))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if model.days.isEmpty {
                Text(model.query.isEmpty ? "No dictations yet" : "No matches")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.footer)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear History…") { confirmingClear = true }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .confirmationDialog(
            "Delete every stored dictation?",
            isPresented: $confirmingClear
        ) {
            Button("Clear History", role: .destructive) {
                Task { await model.clear() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// One dictation: app glyph, up to two lines of text, the meta line, and the
/// actions that appear on hover or selection.
private struct HistoryRow: View {
    let row: HistoryListModel.Row
    let showsActions: Bool
    let pasteTitle: String?
    let canPaste: Bool
    let onPaste: () -> Void
    let onCorrect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(row.glyph.color)
                .frame(width: 30, height: 30)
                .overlay(
                    Text(row.glyph.letters)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(row.text)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // The actions share the meta line and stay in the layout when hidden,
                // so hovering a row changes nothing about its width or height and the
                // text above never rewraps.
                HStack(spacing: 8) {
                    Text(row.meta)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    actions
                        .opacity(showsActions ? 1 : 0)
                        .allowsHitTesting(showsActions)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var actions: some View {
        // Colour the labels, not the buttons: a tinted bordered button also tints its
        // background, and these four should read as one row of identical controls.
        // An explicit label colour does not dim itself when disabled, so Paste picks
        // its own.
        HStack(spacing: 6) {
            if let pasteTitle {
                Button(action: onPaste) {
                    Text(pasteTitle).foregroundStyle(canPaste ? Color.accentColor : Color.secondary)
                }
                .disabled(!canPaste)
            }
            Button("Correct…", action: onCorrect)
            Button("Copy", action: onCopy)
            Button(action: onDelete) {
                Text("Delete").foregroundStyle(Color.red)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }
}
