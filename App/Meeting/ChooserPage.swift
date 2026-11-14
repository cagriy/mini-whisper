import MWMeetings
import SwiftUI

/// The chooser (design §5.9 *Chooser and Test Call setup*): the two modes, the system-audio note
/// before the first remote meeting, the engine, then Start; or the test-call setup in its place.
struct ChooserPage: View {
    @Bindable var model: MeetingWindowModel
    let actions: MeetingActions

    private var chooser: MeetingWindowModel.Chooser { model.chooser }

    var body: some View {
        if model.showsTestCallSetup {
            TestCallSetupView(model: model, actions: actions)
        } else {
            cards
        }
    }

    private var cards: some View {
        PageColumn("Start a meeting") {
            Text(
                "Mini Whisper transcribes the meeting live with speaker labels, keeps your typed notes"
                    + " beside it, and writes a summary when you stop."
            )
            .textStyle(.body)
            .foregroundStyle(DS.Colors.textSecondary)
            .padding(.top, -DS.Space.s5)
            HStack(alignment: .top, spacing: DS.Space.s6) {
                card(.remote)
                card(.inRoom)
            }
            .fixedSize(horizontal: false, vertical: true)
            if chooser.showsSystemAudioNote(for: model.mode) {
                StatusLine(MeetingWindowModel.Chooser.systemAudioNote, .info)
            }
            if let error = model.errorMessage {
                ErrorLine(error)
            }
            if let reason = chooser.startBlockedReason {
                Text(reason).textStyle(.body).foregroundStyle(DS.Colors.textSecondary)
            } else if let engine = chooser.engineLine {
                HStack(spacing: 0) {
                    Text("\(engine) · change under ")
                    Button("Settings → Meetings", action: actions.openSettings)
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.Colors.accent)
                }
                .textStyle(.body)
                .foregroundStyle(DS.Colors.textSecondary)
            }
            HStack(spacing: DS.Space.s4) {
                Button("Test Call…", action: model.openTestCallSetup)
                    .buttonStyle(.pill(.quiet))
                    .disabled(!model.setup.canOpen || chooser.startBlockedReason != nil)
                    .help(model.setup.linkHelp ?? "")
                Spacer(minLength: 0)
                Button("Cancel", action: actions.cancel)
                    .buttonStyle(.pill())
                    .keyboardShortcut(.cancelAction)
                Button("Start", action: actions.start)
                    .buttonStyle(.pill(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStart)
            }
        }
    }

    private func card(_ mode: MeetingMode) -> some View {
        let unavailable = mode == .remote ? chooser.remoteUnavailableReason : nil
        let selected = model.mode == mode
        return Button {
            model.mode = mode
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(spacing: DS.Space.s4) {
                    Text(MeetingWindowModel.title(of: mode)).textStyle(.rowTitle).foregroundStyle(DS.Colors.text)
                    Spacer(minLength: 0)
                    Circle()
                        .strokeBorder(selected ? DS.Colors.accent : DS.Colors.textTertiary, lineWidth: selected ? 5 : 1.5)
                        .frame(width: 16, height: 16)
                }
                Text(chooser.description(of: mode))
                    .textStyle(.meta)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let text = unavailable ?? chooser.priceLabel {
                    Text(text).textStyle(.meta).monospacedDigit().foregroundStyle(DS.Colors.textSecondary)
                }
            }
            .padding(16 + DS.Size.hairline)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.Colors.card))
            // The selected card's border is doubled by a ring of the same colour.
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .strokeBorder(selected ? DS.Colors.accent : DS.Colors.line, lineWidth: selected ? 2 : DS.Size.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        }
        .buttonStyle(.plain)
        .disabled(unavailable != nil)
        .opacity(unavailable == nil ? 1 : 0.5)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
