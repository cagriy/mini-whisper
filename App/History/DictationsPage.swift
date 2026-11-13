import SwiftUI

/// The Dictations page (design §5.9, §5.13, R20): the retention line with Clear…, then the
/// stored dictations by day, each with Paste into *app*, Correct…, Copy and Delete.
struct DictationsPage: View {
    let model: HistoryListModel
    @Binding var confirmingClear: Bool

    var body: some View {
        PageColumn("Dictations") {
            HStack(spacing: DS.Space.s5) {
                Text(model.footer)
                Button("Clear…") { confirmingClear = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Colors.recording)
            }
            .textStyle(.body)
            .foregroundStyle(DS.Colors.textSecondary)
            .padding(.top, -DS.Space.s5)
            ScrollViewReader { proxy in
                LazyVStack(alignment: .leading, spacing: DS.Space.s1) {
                    ForEach(model.days) { day in
                        DayHeader(day.title)
                        ForEach(day.rows) { row in rowView(row).id(row.id) }
                    }
                }
                .onAppear { reveal(model.selection, with: proxy) }
                .onChange(of: model.selection) { reveal(model.selection, with: proxy) }
            }
        }
    }

    private func reveal(_ id: String?, with proxy: ScrollViewProxy) {
        guard let id else { return }
        proxy.scrollTo(id, anchor: .center)
    }

    private func rowView(_ row: HistoryListModel.Row) -> some View {
        ListRow(selected: model.selection == row.id, activate: { model.selection = row.id }) {
            Tile(glyph: row.glyph)
        } content: { active in
            VStack(alignment: .leading, spacing: 0) {
                Text(row.text)
                    .textStyle(.body)
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(2)
                HStack(spacing: DS.Space.s4) {
                    Text(row.meta)
                        .textStyle(.meta)
                        .monospacedDigit()
                        .foregroundStyle(DS.Colors.textTertiary)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    // Kept in the layout when hidden, so hovering never rewraps the text.
                    actions(row)
                        .fixedSize()
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
                }
                .frame(minHeight: DS.Size.controlSmall)
            }
        }
    }

    private func actions(_ row: HistoryListModel.Row) -> some View {
        HStack(spacing: DS.Space.s3) {
            if let pasteTitle = model.pasteTitle {
                Button(pasteTitle) { Task { await model.paste(row) } }
                    .buttonStyle(.pill(size: .small, tint: DS.Colors.accent))
                    .disabled(!model.canPaste)
            }
            Button("Correct…") { model.correct(row) }
                .buttonStyle(.pill(size: .small))
            Button("Copy") { model.copy(row) }
                .buttonStyle(.pill(size: .small))
            Button("Delete") { Task { await model.delete(row) } }
                .buttonStyle(.pill(size: .small, tint: DS.Colors.recording))
        }
    }
}
