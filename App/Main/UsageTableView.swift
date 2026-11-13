import MWUsage
import SwiftUI

/// The sidebar's foot (design §5.9, R21): today's and this month's tokens, audio and cost.
struct UsageTableView: View {
    let table: UsageTable

    var body: some View {
        // A modifier on a `GridRow` would turn it into a single cell, so each cell is styled.
        Grid(alignment: .trailing, horizontalSpacing: DS.Space.s5, verticalSpacing: DS.Space.s1) {
            GridRow {
                Color.clear.gridCellUnsizedAxes(.vertical)
                cell("Tokens in/out", .usageHeader)
                cell("Audio", .usageHeader)
                cell("Cost", .usageHeader)
            }
            row("Today", table.today)
            row("Month", table.month)
        }
        .foregroundStyle(DS.Colors.textTertiary)
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: DS.Space.s5, leading: DS.Space.s2, bottom: 0, trailing: DS.Space.s2))
        .overlay(alignment: .top) { Rectangle().fill(DS.Colors.line).frame(height: DS.Size.hairline) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Usage")
    }

    private func row(_ label: String, _ cells: UsageTable.Row) -> some View {
        GridRow {
            // The label column takes the spare width, so the figures are never cut.
            cell(label, .usage)
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridColumnAlignment(.leading)
            cell(cells.tokens, .usage)
            cell(cells.audio, .usage)
            cell(cells.cost, .usage)
        }
    }

    private func cell(_ text: String, _ style: DS.TextStyle) -> some View {
        Text(text).textStyle(style).fixedSize()
    }
}
