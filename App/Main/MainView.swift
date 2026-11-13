import SwiftUI

/// The main window's content (mockup `mockup-v6-overview.html`): the sidebar, the page of the
/// current destination, and an in-window confirmation over both.
struct MainView: View {
    let model: MainWindowModel

    @State private var confirmingClear = false
    @State private var confirmingSettingsClear = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: 248)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DS.Colors.canvas)
        .ignoresSafeArea()
        .overlay { dialog }
    }

    @ViewBuilder private var page: some View {
        switch model.navigation.destination {
        case .meetings: MeetingsPage(model: model.meetings)
        case .dictations: DictationsPage(model: model.dictations, confirmingClear: $confirmingClear)
        case .search: SearchPage(model: model)
        case .settings: SettingsPage(model: model.settings, confirmingClear: $confirmingSettingsClear)
        // A meeting still opens its own window.
        case .meeting: DS.Colors.canvas
        }
    }

    @ViewBuilder private var dialog: some View {
        if let deletion = model.meetings.pendingDeletion {
            DSDialog(
                title: deletion.prompt,
                message: deletion.detail,
                confirmTitle: deletion.confirmTitle,
                confirm: { Task { await model.meetings.confirmDeletion() } },
                cancel: model.meetings.cancelDeletion
            )
        } else if confirmingClear {
            DSDialog(
                title: "Delete every stored dictation?",
                confirmTitle: "Clear History",
                confirm: {
                    confirmingClear = false
                    Task { await model.dictations.clear() }
                },
                cancel: { confirmingClear = false }
            )
        } else if confirmingSettingsClear {
            DSDialog(
                title: "Delete every stored dictation?",
                confirmTitle: "Clear History",
                confirm: {
                    confirmingSettingsClear = false
                    Task { await model.settings.clearHistory() }
                },
                cancel: { confirmingSettingsClear = false }
            )
        }
    }
}
