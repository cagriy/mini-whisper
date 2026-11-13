import MWMeetings
import SwiftUI

/// The Summary tab: the progress line, why there is no summary, or the blocks in the reading
/// column with the meta line beneath a hairline (design §5.9 *Finished meeting*).
struct SummaryView: View {
    let panel: MeetingWindowModel.SummaryPanel
    let summarise: @MainActor () -> Void

    var body: some View {
        switch panel {
        case .writing:
            StatusLine("Writing the summary…")
        case .message(let text, let canSummarise):
            StatusLine(text, .warning) {
                if canSummarise {
                    Button("Summarise", action: summarise).buttonStyle(.pill(size: .small))
                }
            }
        case .ready(let blocks, let meta, let notice):
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                switch notice {
                case .rewriting: StatusLine("Writing a new summary. This one stays until it arrives.")
                case .failed(let reason): StatusLine("Not regenerated: \(reason)", .warning)
                case nil: EmptyView()
                }
                SummaryBlocks(blocks: blocks, meta: meta)
            }
        }
    }
}

private struct SummaryBlocks: View {
    let blocks: [SummaryDocument.Block]
    let meta: String

    var body: some View {
        let styles = Self.headingStyles(blocks)
        VStack(alignment: .leading, spacing: 0) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(blocks.indices, id: \.self) { index in
                    block(blocks[index], styles: styles)
                        .padding(.top, index == 0 ? 0 : Self.spacing(before: blocks[index], after: blocks[index - 1]))
                }
            }
            Text(meta)
                .textStyle(.meta)
                .monospacedDigit()
                .foregroundStyle(DS.Colors.textTertiary)
                .padding(.top, DS.Space.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(DS.Colors.line).frame(height: DS.Size.hairline) }
                .padding(.top, DS.Space.s8)
        }
        .textSelection(.enabled)
        .frame(maxWidth: DS.Size.readingColumn, alignment: .leading)
    }

    @ViewBuilder private func block(_ block: SummaryDocument.Block, styles: [Int: DS.TextStyle]) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(SummaryDocument.inline(text))
                .textStyle(styles[level] ?? .heading)
                .foregroundStyle(DS.Colors.text)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            reading(text, color: DS.Colors.text)
        case .item(let depth, let ordinal, let text):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(ordinal.map { "\($0)." } ?? "•")
                    .textStyle(.reading)
                    .monospacedDigit()
                    .foregroundStyle(DS.Colors.textTertiary)
                    .frame(width: SummaryRichText.indent, alignment: .leading)
                reading(text, color: depth == 0 ? DS.Colors.text : DS.Colors.textSecondary)
            }
            .padding(.leading, SummaryRichText.indent * CGFloat(depth))
        case .rule:
            Rectangle().fill(DS.Colors.line).frame(height: DS.Size.hairline).padding(.vertical, DS.Space.s4)
        case .code(let text):
            Text(text)
                .textStyle(.mono)
                .foregroundStyle(DS.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(DS.Space.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DS.Radius.row).fill(DS.Colors.card))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.row).strokeBorder(DS.Colors.line))
        }
    }

    private func reading(_ text: String, color: Color) -> some View {
        Text(SummaryDocument.inline(text))
            .textStyle(.reading)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The top-level heading at `heading` whatever its `#` count, the next level present at
    /// `heading2`, the one after at `heading3`.
    private static func headingStyles(_ blocks: [SummaryDocument.Block]) -> [Int: DS.TextStyle] {
        let levels = Set(blocks.compactMap { block -> Int? in
            if case .heading(let level, _) = block { level } else { nil }
        }).sorted()
        let styles: [DS.TextStyle] = [.heading, .heading2, .heading3]
        return Dictionary(uniqueKeysWithValues: levels.enumerated().map { ($1, styles[min($0, styles.count - 1)]) })
    }

    /// As the mockup's reading column: 22 points above a heading, 6 under it, 4 between items.
    private static func spacing(before block: SummaryDocument.Block, after previous: SummaryDocument.Block) -> CGFloat {
        switch (previous, block) {
        case (_, .heading): 22
        case (.heading, _): DS.Space.s3
        case (.item, .item): DS.Space.s2
        default: DS.Space.s5
        }
    }
}
