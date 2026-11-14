import MWMeetings
import SwiftUI

/// Design §5.9 *Live meeting*: the script in place of the notes, the current line on an
/// accent-soft card.
struct ScriptPane: View {
    let model: TestCallPaneModel
    let skip: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: model.title, trailing: model.progress)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s5) {
                    ForEach(model.earlier) { ScriptLineRow(line: $0, place: .earlier) }
                    if let current = model.current, let tag = model.turnTag {
                        ScriptLineRow(line: current, place: .current(tag))
                    }
                    ForEach(model.upcoming) { ScriptLineRow(line: $0, place: .upcoming) }
                    if let more = model.moreLines {
                        Text(more).textStyle(.meta).foregroundStyle(DS.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, DS.Space.s7)
                .padding(.vertical, DS.Space.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(model.notices, id: \.self) { notice in
                StatusLine(notice, .warning)
            }
            HStack(spacing: DS.Space.s5) {
                if let hint = model.hint {
                    Text(hint)
                        .textStyle(.meta)
                        .foregroundStyle(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Skip line", action: skip)
                    .buttonStyle(.pill(size: .small))
                    .disabled(!model.canSkip)
            }
            .padding(.horizontal, DS.Space.s7)
            .padding(.top, DS.Space.s6 + DS.Size.hairline)
            .padding(.bottom, DS.Space.s6)
            .hairline(.top)
        }
        .sidePane()
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

    private var isCurrent: Bool {
        if case .current = place { true } else { false }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            Text("\(line.number)")
                .textStyle(.body.weight(.medium))
                .monospacedDigit()
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                label
                Text(line.text)
                    .textStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(place == .earlier ? DS.Colors.textTertiary : isCurrent ? DS.Colors.text : DS.Colors.textSecondary)
        .padding(isCurrent ? DS.Space.s5 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isCurrent { RoundedRectangle(cornerRadius: DS.Radius.row).fill(DS.Colors.accentSoft) }
        }
    }

    @ViewBuilder private var label: some View {
        switch place {
        case .current(let tag) where tag.isVoice:
            HStack(spacing: DS.Space.s2) {
                LevelBars(color: color)
                Text(tag.text).textStyle(.label).foregroundStyle(color)
            }
        case .current:
            Text("Your line — read it aloud").textStyle(.label).foregroundStyle(DS.Colors.accent)
        case .earlier:
            HStack(spacing: DS.Space.s3) {
                Text(line.speaker).textStyle(.label)
                if line.skipped { LineBadge(text: "Skipped", color: DS.Colors.textSecondary) }
            }
        case .upcoming:
            Text(line.speaker).textStyle(.label).foregroundStyle(color)
        }
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

/// A small capsule label on a script or score line, in `color`.
struct LineBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .textStyle(.label)
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, DS.Space.s3 + DS.Size.hairline)
            .background(Capsule().fill(DS.Colors.card))
            .overlay(Capsule().strokeBorder(DS.Colors.line))
            .fixedSize()
    }
}

extension SpeakerColor {
    /// The user in the accent colour; voices A and B as the engine's first two labels.
    static func of(_ role: TestCallRole) -> Color {
        switch role {
        case .you: user
        case .a: palette[0]
        case .b: palette[1]
        }
    }
}
