import MWMeetings
import SwiftUI

/// Design §5.4 After Stop and on reopen (mockup `mockup-v5-pane-score.html`): the score in place
/// of the script, a badge per line, and a clicked line's script and heard text.
struct ScorePane: View {
    let model: TestCallPaneModel
    let loadRuns: @MainActor () async -> Void
    @State private var showsRuns = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Score", trailing: model.scoreTitle)
            Divider()
            head
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.scoreRows) { row in
                        ScoreLineRow(row: row, expanded: model.expanded == row.number) { model.toggle(row.number) }
                        if model.expanded == row.number, let detail = model.detail {
                            LineDetailCard(detail: detail, color: SpeakerColor.of(row.role))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            Divider()
            HStack(spacing: 10) {
                Button("Earlier runs…") { showsRuns = true }
                    .controlSize(.small)
                    .disabled(model.runRows.isEmpty)
                if let footer = model.runsFooter {
                    Text(footer).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .task { await loadRuns() }
        .sheet(isPresented: $showsRuns) { EarlierRunsSheet(model: model) }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let message = model.scoreMessage {
                Text(message).font(.callout).foregroundStyle(.orange)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(model.overallWER).font(.system(size: 30, weight: .semibold)).monospacedDigit()
                    Text(model.overallDetail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    ForEach(model.roleRows, id: \.role) { row in
                        GridRow(alignment: .firstTextBaseline) {
                            HStack(spacing: 6) {
                                Circle().fill(SpeakerColor.of(row.role)).frame(width: 8, height: 8)
                                Text(row.name) + Text(" · \(row.detail)").foregroundColor(.secondary)
                            }
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.wer).monospacedDigit().gridColumnAlignment(.trailing)
                            (Text(row.label ?? "") + Text(" ")
                                + Text(row.purity ?? "").foregroundColor(row.clean ? .secondary : .orange))
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
                .font(.system(size: 12))
                Text(model.latencyLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TestTag.fill.opacity(0.45))
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ScoreLineRow: View {
    let row: TestCallPaneModel.ScoreRow
    let expanded: Bool
    let toggle: @MainActor () -> Void

    private var color: Color { SpeakerColor.of(row.role) }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text("\(row.number)")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
                (Text(row.speaker).font(.system(size: 11, weight: .semibold)).foregroundColor(color)
                    + Text(" ") + Text(row.text))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    ForEach(row.badges, id: \.text) { badge in
                        LineBadge(text: badge.text, color: Self.color(of: badge.kind)).help(badge.help ?? "")
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background { if expanded { LineRing(color: color) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func color(of kind: TestCallPaneModel.Badge.Kind) -> Color {
        switch kind {
        case .ok: .green
        case .errors: .red
        case .neutral: .secondary
        case .label: .orange
        }
    }
}

/// An expanded score line: the script with the missed words emphasised, then what the engine
/// heard, its errors on a red tint under the script words they replaced.
private struct LineDetailCard: View {
    let detail: TestCallPaneModel.LineDetail
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            caption(detail.scriptTitle)
            detail.script.enumerated().reduce(Text("")) { text, item in
                let word = Text((item.offset == 0 ? "" : " ") + item.element.text)
                return text + (item.element.emphasised ? word.bold() : word)
            }
            .fixedSize(horizontal: false, vertical: true)
            caption(detail.heardTitle).padding(.top, 2)
            WordFlow {
                ForEach(Array(detail.heard.enumerated()), id: \.offset) { _, heard in HeardWord(heard: heard) }
            }
            Text(detail.summary).font(.system(size: 10.5)).foregroundStyle(.secondary).padding(.top, 2)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color))
        .padding(.bottom, 4)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.secondary)
    }
}

private struct HeardWord: View {
    let heard: TestCallRecord.Heard

    private static let errorText = Color(red: 0.63, green: 0.09, blue: 0.09)

    var body: some View {
        switch heard.op {
        case .match:
            Text(heard.text ?? "")
        case .error:
            VStack(spacing: 0) {
                if let script = heard.script, !script.isEmpty {
                    Text(script).font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
                Text(heard.text ?? "")
                    .foregroundStyle(Self.errorText)
                    .padding(.horizontal, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.1)))
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
