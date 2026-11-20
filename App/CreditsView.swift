import SwiftUI

/// The Credits window's content: a lead line, then a card with a row per bundled component.
struct CreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                Text("Mini Whisper includes the work of others.")
                    .textStyle(.body)
                    .foregroundStyle(DS.Colors.textSecondary)
                Card {
                    ForEach(Credits.entries, id: \.name, content: CreditRow.init)
                }
            }
            .smallWindowBody(top: DS.Space.s2)
        }
        .background(DS.Colors.canvas)
    }
}

/// A component's name and purpose, who made it, and its licence with one quiet action.
private struct CreditRow: View {
    let entry: Credits.Entry

    @State private var showsLicence = false

    var body: some View {
        SettingRow.full(spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s5) {
                Text(entry.name)
                    .textStyle(.rowTitle)
                    .foregroundStyle(DS.Colors.text)
                Text(entry.purpose)
                    .textStyle(.meta)
                    .foregroundStyle(DS.Colors.textTertiary)
            }
            Text(entry.attribution)
                .textStyle(.body)
                .foregroundStyle(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            licenceLine
                .padding(.top, DS.Space.s1)
            if showsLicence, let text = entry.licenceText {
                licenceBox(text)
                    .padding(.top, DS.Space.s3)
            }
        }
    }

    /// The licence, then its action at the right, or on a line of its own when both do not fit.
    private var licenceLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s4) {
                licenceName
                Spacer(minLength: 0)
                licenceAction
            }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                licenceName
                licenceAction
            }
        }
        .foregroundStyle(DS.Colors.textSecondary)
        .buttonStyle(.pill(.quietAction, size: .small))
    }

    private var licenceName: some View {
        HStack(spacing: DS.Space.s4) {
            Text(entry.licence)
                .textStyle(.meta)
            if let address = entry.licenceAddress {
                Text(address)
                    .textStyle(.mono)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var licenceAction: some View {
        if let url = entry.licenceURL {
            Button("Open Licence…") { NSWorkspace.shared.open(url) }
        } else if entry.licenceText != nil {
            Button(showsLicence ? "Hide Licence" : "Show Licence") { showsLicence.toggle() }
        }
    }

    /// The bundled licence in full, in a monospaced box of its own that scrolls.
    private func licenceBox(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .textStyle(.mono)
                .foregroundStyle(DS.Colors.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s6 + DS.Size.hairline)
                .padding(.vertical, DS.Space.s5 + DS.Size.hairline)
        }
        .frame(height: 150)
        .background(RoundedRectangle(cornerRadius: DS.Radius.field).fill(DS.Colors.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.field).strokeBorder(DS.Colors.line))
    }
}
