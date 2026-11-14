import MWMeetings
import SwiftUI

/// Design §5.9 *Finished meeting*: a test call's score beside its transcript, a badge per line,
/// and a clicked line's script and heard text.
struct ScorePane: View {
    let model: TestCallPaneModel
    let loadRuns: @MainActor () async -> Void
    @State private var showsRuns = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Score", trailing: model.scoreTitle)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s5) {
                    head
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        ForEach(model.scoreRows) { row in
                            ScoreLineRow(row: row, expanded: model.expanded == row.number) { model.toggle(row.number) }
                            if model.expanded == row.number, let detail = model.detail {
                                LineDetailCard(detail: detail, color: SpeakerColor.of(row.role))
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s7)
                .padding(.vertical, DS.Space.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: DS.Space.s5) {
                if let footer = model.runsFooter {
                    Text(footer).textStyle(.meta).foregroundStyle(DS.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                Button("Earlier runs…") { showsRuns = true }
                    .buttonStyle(.pill(size: .small))
                    .disabled(model.runRows.isEmpty)
            }
            .padding(.horizontal, DS.Space.s7)
            .padding(.top, DS.Space.s6 + DS.Size.hairline)
            .padding(.bottom, DS.Space.s6)
            .hairline(.top)
        }
        .sidePane()
        .task { await loadRuns() }
        .sheet(isPresented: $showsRuns) { EarlierRunsSheet(model: model) }
    }

    @ViewBuilder private var head: some View {
        if let message = model.scoreMessage {
            Text(message).textStyle(.body).foregroundStyle(DS.Colors.warn).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.overallWER).textStyle(.score).monospacedDigit().foregroundStyle(DS.Colors.text)
                    Text(model.overallDetail).textStyle(.meta).foregroundStyle(DS.Colors.textSecondary)
                }
                // Each role's rate; its engine label and purity in the help text.
                FlowLayout {
                    ForEach(model.roleRows, id: \.role) { row in
                        Chip("\(row.name) \(row.wer)", row.clean ? .plain : .warning)
                            .help(([row.detail] + [row.label, row.purity].compactMap { $0 }).joined(separator: " · "))
                    }
                }
                Text(model.latencyLine)
                    .textStyle(.meta)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ScoreLineRow: View {
    let row: TestCallPaneModel.ScoreRow
    let expanded: Bool
    let toggle: @MainActor () -> Void

    private var color: Color { SpeakerColor.of(row.role) }

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                Text("\(row.number)")
                    .textStyle(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(DS.Colors.textTertiary)
                    .frame(width: 18, alignment: .leading)
                (Text(row.speaker).fontWeight(.semibold).foregroundStyle(color) + Text(" ") + Text(row.text))
                    .textStyle(.body)
                    .foregroundStyle(expanded ? DS.Colors.text : DS.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: DS.Space.s2) {
                    ForEach(row.badges, id: \.text) { badge in
                        LineBadge(text: badge.text, color: Self.color(of: badge.kind)).help(badge.help ?? "")
                    }
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, DS.Space.s3)
            .background {
                if expanded { RoundedRectangle(cornerRadius: DS.Radius.row).fill(DS.Colors.accentSoft) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func color(of kind: TestCallPaneModel.Badge.Kind) -> Color {
        switch kind {
        case .ok: DS.Colors.ok
        case .errors: DS.Colors.recording
        case .neutral: DS.Colors.textSecondary
        case .label: DS.Colors.warn
        }
    }
}

/// An expanded score line: the script with the missed words emphasised, then what the engine
/// heard, its errors on a tint under the script words they replaced.
private struct LineDetailCard: View {
    let detail: TestCallPaneModel.LineDetail
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            caption(detail.scriptTitle)
            detail.script.enumerated().reduce(Text("")) { text, item in
                let word = Text((item.offset == 0 ? "" : " ") + item.element.text)
                return text + (item.element.emphasised ? word.bold() : word)
            }
            .fixedSize(horizontal: false, vertical: true)
            caption(detail.heardTitle).padding(.top, DS.Space.s1)
            WordFlow {
                ForEach(Array(detail.heard.enumerated()), id: \.offset) { _, heard in HeardWord(heard: heard) }
            }
            Text(detail.summary).textStyle(.meta).foregroundStyle(DS.Colors.textSecondary).padding(.top, DS.Space.s1)
        }
        .textStyle(.body)
        .foregroundStyle(DS.Colors.text)
        .padding(.horizontal, DS.Space.s5 + DS.Size.hairline)
        .padding(.vertical, DS.Space.s4 + DS.Size.hairline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.field).fill(DS.Colors.card))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.field).strokeBorder(color))
        .padding(.bottom, DS.Space.s2)
    }

    private func caption(_ text: String) -> some View {
        Text(text).textStyle(.label).foregroundStyle(DS.Colors.textSecondary)
    }
}

private struct HeardWord: View {
    let heard: TestCallRecord.Heard

    private static let errorText = DS.Colors.recording

    var body: some View {
        switch heard.op {
        case .match:
            Text(heard.text ?? "")
        case .error:
            VStack(spacing: 0) {
                if let script = heard.script, !script.isEmpty {
                    Text(script).font(.system(size: 9.5)).foregroundStyle(DS.Colors.textSecondary)
                }
                Text(heard.text ?? "")
                    .foregroundStyle(Self.errorText)
                    .padding(.horizontal, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(DS.Colors.recordingSoft))
            }
        case .missed:
            Text(heard.script ?? "").strikethrough(color: Self.errorText).foregroundStyle(Self.errorText)
        }
    }
}

/// Words left to right, wrapping at the proposed width, each line bottom-aligned so a word with
/// its script word above it keeps the line's baseline.
private struct WordFlow: Layout {
    private static let spacing: CGFloat = 3.5
    private static let lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(of: subviews, width: proposal.width ?? .infinity)
        let width = lines.map { $0.width }.max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + Self.lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(of: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + line.height - size.height), proposal: .unspecified)
                x += size.width + Self.spacing
            }
            y += line.height + Self.lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(of subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = line.indices.isEmpty ? size.width : line.width + Self.spacing + size.width
            if needed > width, !line.indices.isEmpty {
                lines.append(line)
                line = Line()
            }
            line.width = line.indices.isEmpty ? size.width : line.width + Self.spacing + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
        }
        if !line.indices.isEmpty { lines.append(line) }
        return lines
    }
}

/// Design §3 R19: the runs of this scenario revision on this Mac, this one in bold.
struct EarlierRunsSheet: View {
    let model: TestCallPaneModel
    @Environment(\.dismiss) private var dismiss

    /// WER and the three roles' rates read right-aligned.
    private static let numeric: Set<Int> = [2, 3, 4, 5]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.runsTitle).font(.system(size: 13, weight: .semibold))
            Text(model.runsNote)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        ForEach(Array(model.runColumns.enumerated()), id: \.offset) { column, title in
                            Text(title.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(Self.numeric.contains(column) ? .trailing : .leading)
                                .help(title == "Clean" ? TestCallPaneModel.cleanDefinition : "")
                        }
                    }
                    Divider()
                    ForEach(model.runRows) { row in
                        GridRow {
                            Text(row.run).monospacedDigit()
                            Text(row.engine)
                            Text(row.wer)
                            ForEach(Array(row.roles.enumerated()), id: \.offset) { _, rate in Text(rate) }
                            Text(row.clean)
                            Text(row.latency)
                        }
                        .monospacedDigit()
                        .fontWeight(row.isThis ? .semibold : .regular)
                        Divider()
                    }
                }
                .font(.system(size: 11.5))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
        .frame(width: 660)
    }
}
