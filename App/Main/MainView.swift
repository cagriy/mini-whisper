import SwiftUI

/// The main window's content (mockup `mockup-v6-overview.html`): the sidebar, the page of the
/// current destination, and an in-window confirmation over both.
struct MainView: View {
    let model: MainWindowModel

    @State private var confirmingClear = false
    @State private var confirmingSettingsClear = false
    @State private var meetingDialog: PageDialog?

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
        // A confirmation belongs to the meeting page it was asked on.
        .onChange(of: model.navigation.destination) { meetingDialog = nil }
        .onChange(of: model.presented.map { ObjectIdentifier($0.model) }) { meetingDialog = nil }
    }

    @ViewBuilder private var page: some View {
        switch model.navigation.destination {
        case .meetings: MeetingsPage(model: model.meetings)
        case .dictations: DictationsPage(model: model.dictations, confirmingClear: $confirmingClear)
        case .search: SearchPage(model: model)
        case .settings: SettingsPage(model: model.settings, confirmingClear: $confirmingSettingsClear)
        case .meeting:
            if let meeting = model.presented {
                MeetingPage(
                    model: meeting.model, actions: meeting.actions, backLabel: model.navigation.backLabel,
                    dialog: $meetingDialog
                )
                // Each session's page starts with its own editing and popover state.
                .id(ObjectIdentifier(meeting.model))
            } else {
                DS.Colors.canvas
            }
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
        } else if let meetingDialog {
            DSDialog(
                title: meetingDialog.title,
                message: meetingDialog.message,
                confirmTitle: meetingDialog.confirmTitle,
                confirm: {
                    self.meetingDialog = nil
                    meetingDialog.confirm()
                },
                cancel: { self.meetingDialog = nil }
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
