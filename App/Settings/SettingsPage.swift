import SwiftUI

/// Settings (design §5.9, R22): the section the sidebar selects, as a page of cards.
struct SettingsPage: View {
    let model: SettingsModel
    /// Clear History's confirmation, which the window lays over the sidebar too.
    @Binding var confirmingClear: Bool

    var body: some View {
        PageColumn(model.selection.title) {
            switch model.selection {
            case .general: GeneralSection(model: model)
            case .hotkeys: HotkeysSection(model: model)
            case .keys: KeysSection(model: model)
            case .cleanup: CleanupSection(model: model)
            case .vocabulary: VocabularySection(model: model)
            case .history: HistorySection(model: model, confirmingClear: $confirmingClear)
            case .meetings: MeetingsSection(model: model)
            case .overlay: OverlaySection(model: model)
            case .sound: SoundSection(model: model)
            }
        }
        // Each section opens at its top.
        .id(model.selection)
    }
}

/// A footnote inside a full-width row, set as a row's description is.
struct SettingsFootnote: View {
    private let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .textStyle(.meta)
            .foregroundStyle(DS.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A labelled line of the detail form under a table.
struct DetailRow<Content: View>: View {
    private let label: String
    private let alignment: VerticalAlignment
    private let content: Content

    init(_ label: String, alignment: VerticalAlignment = .center, @ViewBuilder content: () -> Content) {
        self.label = label
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: DS.Space.s4) {
            Text(label)
                .textStyle(.body)
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(width: 90, alignment: .leading)
            content
        }
    }
}

extension View {
    /// A stock table on a card: a field's fill and outline, with no alternating rows.
    func settingsTable(height: CGFloat) -> some View {
        alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
            .background(DS.Colors.canvas)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.field))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.field).strokeBorder(DS.Colors.line))
    }
}

/// A control's binding over one of the model's `async` write-through setters, so
/// every change reaches `config.json` immediately (design §5.4).
@MainActor
func settingsBinding<Value: Sendable>(
    _ value: Value,
    set: @escaping @MainActor (Value) async -> Void
) -> Binding<Value> {
    Binding(get: { value }, set: { new in Task { @MainActor in await set(new) } })
}
