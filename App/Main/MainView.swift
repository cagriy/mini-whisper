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
        // A confirmation belongs to the page it was asked on.
        .onChange(of: model.navigation.destination) {
            meetingDialog = nil
            model.settings.cancelBetaChannel()
            model.settings.cancelReset()
        }
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
        } else if let confirmation = model.settings.people.pending {
            DSDialog(
                title: confirmation.title,
                message: confirmation.message,
                confirmTitle: confirmation.confirmTitle,
                confirm: { Task { await model.settings.people.confirm() } },
                cancel: model.settings.people.cancelConfirmation
            )
        } else if model.settings.confirmingBetaChannel {
            DSDialog(
                title: "Switch to beta versions?",
                message: "Beta versions arrive before each release and may have bugs. You can switch back to"
                    + " Release at any time; an installed beta stays until the next release.",
                confirmTitle: "Switch to Beta",
                confirm: { Task { await model.settings.confirmBetaChannel() } },
                cancel: model.settings.cancelBetaChannel
            )
        } else if model.settings.confirmingReset {
            DSDialog(
                title: "Reset statistics?",
                message: "Totals, records and milestones are erased and rebuilt from what is still stored. Figures"
                    + " from deleted meetings and from dictations already pruned cannot be recovered.",
                confirmTitle: "Reset Statistics",
                confirm: { Task { await model.settings.confirmReset() } },
                cancel: model.settings.cancelReset
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
