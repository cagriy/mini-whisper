import SwiftUI

/// An in-window confirmation: a card over a scrim that covers what it is laid over.
/// Return confirms; Esc and a click on the scrim cancel.
struct DSDialog: View {
    let title: String
    let message: String
    /// The filled button's title.
    let confirmTitle: String
    var cancelTitle = "Cancel"
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            DS.Colors.scrim
                .contentShape(Rectangle())
                .onTapGesture(perform: cancel)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text(title)
                    .textStyle(.titleDialog)
                    .foregroundStyle(DS.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .textStyle(.body)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.s4) {
                    Spacer(minLength: 0)
                    Button(cancelTitle, action: cancel)
                        .buttonStyle(.pill())
                        .keyboardShortcut(.cancelAction)
                    Button(confirmTitle, action: confirm)
                        .buttonStyle(.pill(.primary))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, DS.Space.s5)
            }
            .padding(22 + DS.Size.hairline)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.Colors.card).dialogShadow())
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Colors.line))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isModal)
        }
    }
}
