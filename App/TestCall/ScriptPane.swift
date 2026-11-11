import MWMeetings
import SwiftUI

/// Design §5.4 During the call (mockup `mockup-v5-script-pane.html`): the script in place of the
/// notes, the current line ringed in its speaker's colour.
struct ScriptPane: View {
    let model: TestCallPaneModel
    let skip: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: model.title, trailing: model.progress)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.earlier) { ScriptLineRow(line: $0, place: .earlier) }
                    if let current = model.current, let tag = model.turnTag {
                        ScriptLineRow(line: current, place: .current(tag))
                    }
                    ForEach(model.upcoming) { ScriptLineRow(line: $0, place: .upcoming) }
                    if let more = model.moreLines {
                        Text(more)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(model.notices, id: \.self) { notice in
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // As the window's banners, on the text background the pane's grey would wash out.
                    .background(Color.orange.opacity(0.08))
                    .background(Color(nsColor: .textBackgroundColor))
            }
            Divider()
            HStack(spacing: 10) {
                if let hint = model.hint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Skip line", action: skip)
                    .controlSize(.small)
                    .disabled(!model.canSkip)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct ScriptLineRow: View {
    enum Place: Equatable {
        case earlier
        case current(TestCallPaneModel.TurnTag)
        case upcoming
    }

    let line: TestCallPaneModel.ScriptLine
    let place: Place

    private var color: Color { SpeakerColor.of(line.role) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(line.number)")
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                label
                Text(line.text)
                    .font(.system(size: place == .earlier || place == .upcoming ? 12 : 13))
                    .foregroundStyle(place == .earlier ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if case .current = place { ring }
        }
    }

    @ViewBuilder private var label: some View {
        switch place {
        case .current(let tag):
            HStack(spacing: 0) {
                if tag.isVoice { LevelBars(color: color).padding(.trailing, 4) }
                Text(tag.name.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(color)
                Text(" " + tag.detail)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .earlier:
            HStack(spacing: 6) {
                Text(line.speaker).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                if line.skipped { LineBadge(text: "Skipped", color: .secondary) }
            }
        case .upcoming:
            Text(line.speaker).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
        }
    }

    /// The speaker's colour around a white card, on a blue tint for the user's line.
    private var ring: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 7).fill(line.role == .you ? Color.accentColor.opacity(0.06) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(color))
            .background(RoundedRectangle(cornerRadius: 9).strokeBorder(color.opacity(0.18), lineWidth: 2).padding(-2))
    }
}

/// The speaking voice's three-bar level, static under Reduce Motion.
private struct LevelBars: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let heights: [CGFloat] = [5, 11, 7]
    private static let delays = [0, 0.15, 0.3]
    private static let period = 0.9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { bar in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2.5, height: Self.heights[bar])
                        .scaleEffect(x: 1, y: reduceMotion ? 1 : scale(bar, at: context.date), anchor: .bottom)
                }
            }
            .frame(height: 11, alignment: .bottom)
        }
    }

    /// Full height, down to 40% half a period later, and back.
    private func scale(_ bar: Int, at date: Date) -> CGFloat {
        let time = date.timeIntervalSinceReferenceDate - Self.delays[bar]
        let phase = time.truncatingRemainder(dividingBy: Self.period) / Self.period
        return 0.7 + 0.3 * cos(2 * .pi * phase)
    }
}

/// A small capsule label on a script or score line, tinted in `color`.
struct LineBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.08)))
            .overlay(Capsule().stroke(color.opacity(0.3)))
            .fixedSize()
    }
}

extension SpeakerColor {
    /// The user in the accent colour; voices A and B as the engine's first two labels.
    static func of(_ role: TestCallRole) -> Color {
        switch role {
        case .you: .accentColor
        case .a: palette[0]
        case .b: palette[1]
        }
    }
}
