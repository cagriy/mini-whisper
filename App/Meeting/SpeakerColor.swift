import MWMeetingPipeline
import SwiftUI

/// Speaker colours: the user in the accent colour, others by their label.
enum SpeakerColor {
    static let user = DS.Colors.accent
    static let palette = [DS.Colors.speaker1, DS.Colors.speaker2, DS.Colors.speaker3]

    static func of(_ speaker: Int) -> Color {
        speaker == SpeakerRegistry.userID ? user : palette[abs(speaker - 1) % palette.count]
    }
}

/// A side pane's title, with an optional figure at the right, above a hairline.
struct PaneHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: DS.Space.s4) {
            Text(title)
            Spacer(minLength: DS.Space.s4)
            if let trailing { Text(trailing).monospacedDigit() }
        }
        .lineLimit(1)
        .textStyle(.meta.weight(.semibold))
        .foregroundStyle(DS.Colors.textSecondary)
        .padding(.horizontal, DS.Space.s7)
        .padding(.top, DS.Space.s6)
        .padding(.bottom, DS.Space.s6 + DS.Size.hairline)
        .hairline(.bottom)
    }
}

extension View {
    /// A pane beside the transcript: the sidebar's fill, a hairline at its leading edge.
    func sidePane() -> some View {
        background(DS.Colors.sidebar).hairline(.leading)
    }
}
