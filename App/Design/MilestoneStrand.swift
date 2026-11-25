import SwiftUI

/// Dated items on a hairline rail, oldest first, four to a row, each marked by an accent dot. Items
/// fade in one after another when their panel plays. VoiceOver reads `label`, then each item.
struct MilestoneStrand: View {
    struct Item {
        let date: String
        let title: String
    }

    let items: [Item]
    /// The headline sentence.
    let label: String

    private static let perRow = 4
    /// The accepted mockup's dot, and the ring of canvas that parts the rail around it.
    private static let dot: CGFloat = 9
    private static let ring: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(row, id: \.self) { item($0) }
                    ForEach(row.count..<Self.perRow, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var rows: [[Int]] {
        stride(from: 0, to: items.count, by: Self.perRow).map { Array($0..<min($0 + Self.perRow, items.count)) }
    }

    private func item(_ index: Int) -> some View {
        let item = items[index]
        return VStack(alignment: .leading, spacing: 0) {
            Text(item.date)
                .textStyle(.meta)
                .monospacedDigit()
                .foregroundStyle(DS.Colors.textTertiary)
            Text(item.title)
                .textStyle(DS.TextStyle.body.weight(.medium))
                .foregroundStyle(DS.Colors.text)
        }
        .padding(.top, DS.Space.s6)
        .padding(.trailing, DS.Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairline(.top)
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(DS.Colors.accent)
                .frame(width: Self.dot, height: Self.dot)
                .padding(Self.ring)
                .background(Circle().fill(DS.Colors.canvas))
                .offset(x: -Self.ring, y: -(Self.dot + Self.ring * 2 - DS.Size.hairline) / 2)
        }
        .timelineFade(index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.date)")
    }
}
