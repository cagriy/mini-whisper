import MWOverlaySim
import SwiftUI

/// The style picker of design §5.4, as the accepted `mockup-v3-side-by-side` pane:
/// a compact radio list beside the neutral well the live preview sits in.
struct OverlaySection: View {
    let model: SettingsModel

    var body: some View {
        Card {
            SettingRow.full(spacing: DS.Space.s4) {
                HStack(alignment: .top, spacing: DS.Space.s6) {
                    VStack(spacing: 0) {
                        ForEach(model.overlayStyleRows) { row in
                            styleRow(row)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    well
                }

                SettingsFootnote(
                    "The card appears beside the text field you are dictating into."
                        + " The preview replays a short dictation with a simulated voice."
                )
            }
        }
    }

    private var well: some View {
        OverlayPreview(style: model.selectedOverlayStyle)
            .frame(width: Constants.windowSize, height: Constants.windowSize)
            .frame(width: 316, height: 316)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.Colors.sidebar)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Colors.line)
            }
    }

    /// The engine list's form, with the summary folded away on every row but the
    /// selected one so the six fit without scrolling.
    private func styleRow(_ row: SettingsModel.OverlayStyleRow) -> some View {
        let isSelected = model.selectedOverlayStyle == row.style
        return RadioRow(
            row.title,
            detail: isSelected ? .plain(row.summary) : nil,
            selected: isSelected,
            select: { Task { await model.setOverlayStyle(row.style) } }
        ) {
            if row.isDefault {
                Chip("Default")
            }
        }
    }
}
