import MWStats
import SwiftUI

/// The sidebar's statistics (design §5 Interfaces › Sidebar, R23; mockup `mockup-v11-figures-handle.html`):
/// six figures over the last 30 days, their trend of hours recorded and one lifetime line. The whole
/// block opens Timeline.
struct StatsBlockView: View {
    let stats: SidebarStats
    /// The sidebar drops the trend before it drops the block.
    var showsTrend = true
    let open: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text("Last 30 days")
                    .textStyle(DS.TextStyle.usage.weight(.medium))
                    .foregroundStyle(DS.Colors.textSecondary)
                VStack(spacing: DS.Space.s4) {
                    row(figure(StatFormat.sidebarNumber(stats.meetings), "Meetings"),
                        figure(StatFormat.duration(stats.recorded), "Recorded"))
                    row(figure(StatFormat.sidebarNumber(stats.dictations), "Dictations"),
                        figure(StatFormat.duration(stats.savedTyping), "Saved typing"))
                    row(figure(StatFormat.sidebarNumber(stats.wordsTranscribed), "Words transcribed"),
                        figure(StatFormat.sidebarNumber(stats.wordsDictated), "Words dictated"))
                }
                if showsTrend {
                    StatsTrend(seconds: stats.trend)
                }
                Text(lifetime)
                    .textStyle(.usage)
                    .monospacedDigit()
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.Space.s3)
            .padding(.horizontal, DS.Space.s2)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.field).fill(hovered ? DS.Colors.hover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.field))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityHint("Opens Timeline")
    }

    private var lifetime: String {
        let count = stats.lifetimeMeetings
        return "\(StatFormat.sidebarNumber(count)) \(count == 1 ? "meeting" : "meetings")"
            + " · \(StatFormat.duration(stats.lifetimeRecorded)) all time"
    }

    private func row(_ leading: some View, _ trailing: some View) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s6) {
            leading
            trailing
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .textStyle(.heading3)
                .monospacedDigit()
                .foregroundStyle(DS.Colors.text)
            Text(label)
                .textStyle(.usage)
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hours recorded on each day of the window, oldest first: accent bars, a zero day a tick in `line`.
private struct StatsTrend: View {
    let seconds: [TimeInterval]

    private static let height: CGFloat = 26
    private static let tick: CGFloat = 2

    var body: some View {
        let top = seconds.max() ?? 0
        HStack(alignment: .bottom, spacing: DS.Space.s1) {
            ForEach(seconds.indices, id: \.self) { index in
                let value = seconds[index]
                if value > 0, top > 0 {
                    UnevenRoundedRectangle(topLeadingRadius: DS.Radius.cell, topTrailingRadius: DS.Radius.cell)
                        .fill(DS.Colors.accent)
                        .frame(height: max(Self.tick, Self.height * value / top))
                } else {
                    Rectangle().fill(DS.Colors.line).frame(height: Self.tick)
                }
            }
        }
        .frame(height: Self.height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Folds the stats block: a pill on the usage table's top hairline, its chevron down while the block
/// shows and up once it is folded.
struct StatsFoldHandle: View {
    let folded: Bool
    let toggle: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "chevron.down")
                .font(DS.TextStyle.label.font)
                .rotationEffect(.degrees(folded ? 180 : 0))
                .animation(.easeOut(duration: 0.15), value: folded)
                .foregroundStyle(hovered ? DS.Colors.text : DS.Colors.textTertiary)
                .frame(width: 34, height: 20)
                .background(Capsule().fill(hovered ? DS.Colors.hover : DS.Colors.sidebar))
                .overlay(Capsule().strokeBorder(DS.Colors.line, lineWidth: DS.Size.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(folded ? "Unfold statistics" : "Fold statistics")
    }
}
