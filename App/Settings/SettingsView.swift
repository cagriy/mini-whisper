import SwiftUI

/// The sidebar Settings window of design §5.4, matching the accepted mockup
/// `mockup-v1-settings-sidebar.html`: seven sections on the left, one pane on
/// the right, 780×560.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        NavigationSplitView {
            List(SettingsModel.Section.allCases, selection: $model.selection) { section in
                Label(section.title, systemImage: section.symbolName).tag(section)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            ScrollView {
                pane
            }
        }
        .frame(width: 780, height: 560)
    }

    @ViewBuilder private var pane: some View {
        switch model.selection {
        case .general: GeneralSection(model: model)
        case .hotkeys: HotkeysSection(model: model)
        case .keys: KeysSection(model: model)
        case .cleanup: CleanupSection(model: model)
        case .vocabulary: VocabularySection(model: model)
        case .history: HistorySection(model: model)
        case .sound: SoundSection(model: model)
        }
    }
}

/// One pane: a title and its rows, laid out the same way in every section.
struct SettingsPane<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2.weight(.semibold))
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsFootnote: View {
    private let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
