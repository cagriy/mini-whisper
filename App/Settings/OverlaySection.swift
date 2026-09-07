import SwiftUI

/// The style picker of design §5.4, as the accepted `mockup-v3-side-by-side` pane:
/// a compact radio list beside the neutral well the live preview sits in.
struct OverlaySection: View {
    let model: SettingsModel

    var body: some View {
        SettingsPane(title: "Overlay") {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 5) {
                    ForEach(model.overlayStyleRows) { row in
                        styleRow(row)
                    }
                }
                .frame(width: 214)

                well
            }

            SettingsFootnote(
                "The card appears beside the text field you are dictating into."
                    + " The preview replays a short dictation with a simulated voice."
            )
        }
    }

    private var well: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(nsColor: .underPageBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .frame(width: 316, height: 316)
    }

    /// `GeneralSection.engineRow`'s form, with the summary folded away on every row
    /// but the selected one so the six fit without scrolling.
    private func styleRow(_ row: SettingsModel.OverlayStyleRow) -> some View {
        let isSelected = model.selectedOverlayStyle == row.style
        return Button {
            Task { await model.setOverlayStyle(row.style) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                    if isSelected {
                        Text(row.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if row.isDefault {
                    Text("Default")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor, lineWidth: 1)
                        }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
