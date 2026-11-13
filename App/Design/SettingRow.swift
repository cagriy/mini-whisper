import SwiftUI

/// One row of a card, with a hairline above it that the card's edge covers on the first row.
struct SettingRow<Content: View>: View {
    private let title: String?
    private let description: String?
    private let spacing: CGFloat?
    private let content: Content

    /// The name and its description at the left, the control at the right.
    init(_ title: String, description: String? = nil, @ViewBuilder control: () -> Content) {
        self.init(title: title, description: description, spacing: nil, content: control())
    }

    /// An editor, list or preview across the card's width, under an optional name.
    static func full(
        _ title: String? = nil, spacing: CGFloat = 0, @ViewBuilder content: () -> Content
    ) -> SettingRow {
        SettingRow(title: title, description: nil, spacing: spacing, content: content())
    }

    private init(title: String?, description: String?, spacing: CGFloat?, content: Content) {
        self.title = title
        self.description = description
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        Group {
            if let spacing {
                VStack(alignment: .leading, spacing: spacing) {
                    name
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        name
                        if let description {
                            Text(description)
                                .textStyle(.meta)
                                .foregroundStyle(DS.Colors.textSecondary)
                                .frame(maxWidth: 414, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    content
                }
            }
        }
        .padding(.top, DS.Space.s7 + DS.Size.hairline)
        .padding(.bottom, DS.Space.s7)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Colors.line).frame(height: DS.Size.hairline)
        }
    }

    @ViewBuilder private var name: some View {
        if let title {
            Text(title).textStyle(.body.weight(.medium)).foregroundStyle(DS.Colors.text)
        }
    }
}
