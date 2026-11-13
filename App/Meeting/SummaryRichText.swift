import AppKit
import MWMeetings

/// Copy summary's rich text: the title, then the blocks in the summary's type styles. Fonts and
/// indents only, built from `SummaryDocument.inline`, so no link or image reaches the pasteboard.
enum SummaryRichText {
    /// Each item is indented this much per depth.
    static let indent: CGFloat = 20

    static func rtf(title: String, blocks: [SummaryDocument.Block]) -> Data {
        let text = attributed(title: title, blocks: blocks)
        let range = NSRange(location: 0, length: text.length)
        return (try? text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]))
            ?? Data()
    }

    static func attributed(title: String, blocks: [SummaryDocument.Block]) -> NSAttributedString {
        let levels = Set(blocks.compactMap { block -> Int? in
            if case .heading(let level, _) = block { level } else { nil }
        }).sorted()
        let headings: [DS.TextStyle] = [.heading, .heading2, .heading3]

        var paragraphs = [NSAttributedString(string: title, attributes: [.font: DS.TextStyle.title.nsFont])]
        for block in blocks {
            switch block {
            case .heading(let level, let text):
                let rank = min(levels.firstIndex(of: level) ?? 0, headings.count - 1)
                paragraphs.append(inline(text, font: headings[rank].nsFont))
            case .paragraph(let text):
                paragraphs.append(inline(text, font: DS.TextStyle.reading.nsFont))
            case .item(let depth, let ordinal, let text):
                let marker = ordinal.map { "\($0). " } ?? "• "
                // A continuation line stays inside its item's paragraph.
                let item = NSMutableAttributedString(
                    string: marker, attributes: [.font: DS.TextStyle.reading.nsFont]
                )
                item.append(inline(text.replacingOccurrences(of: "\n", with: "\u{2028}"), font: DS.TextStyle.reading.nsFont))
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = indent * CGFloat(depth)
                style.headIndent = indent * CGFloat(depth)
                item.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: item.length))
                paragraphs.append(item)
            case .rule:
                paragraphs.append(NSAttributedString(string: "———", attributes: [.font: DS.TextStyle.reading.nsFont]))
            case .code(let text):
                paragraphs.append(NSAttributedString(string: text, attributes: [.font: DS.TextStyle.mono.nsFont]))
            }
        }

        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            result.append(paragraph)
            guard index < paragraphs.count - 1 else { break }
            // The break takes its paragraph's font and indent, so other apps size the line by them.
            let last = paragraph.length > 0 ? paragraph.attributes(at: paragraph.length - 1, effectiveRange: nil) : [:]
            result.append(NSAttributedString(
                string: "\n", attributes: last.filter { $0.key == .font || $0.key == .paragraphStyle }
            ))
        }
        return result
    }

    /// The inline Markdown of one block: bold, italic and code as fonts, strikethrough as itself.
    private static func inline(_ text: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let parsed = SummaryDocument.inline(text)
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var runFont = intent.contains(.code)
                ? NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                : font
            var traits = runFont.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if traits != runFont.fontDescriptor.symbolicTraits {
                runFont = NSFont(descriptor: runFont.fontDescriptor.withSymbolicTraits(traits), size: runFont.pointSize)
                    ?? runFont
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: runFont]
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }
}
