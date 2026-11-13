import AppKit
import MWMeetings
import Testing
@testable import MiniWhisper

@Suite struct SummaryRichTextTests {
    private static let title = "Weekly platform sync"
    private static let blocks = SummaryDocument(markdown: """
        ## Catalog entries
        - Existing entries were **reviewed**
          - Harbour billing
            - Invoices
        Owners stay *as they are*.
        1. Tomas adds the projects
        ---
        ```
        let x = 1
        ```
        """).blocks

    private static func readBack(_ data: Data) throws -> NSAttributedString {
        try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    }

    private static let expected = [
        "Weekly platform sync",
        "Catalog entries",
        "• Existing entries were reviewed",
        "• Harbour billing",
        "• Invoices",
        "Owners stay as they are.",
        "1. Tomas adds the projects",
        "———",
        "let x = 1",
    ].joined(separator: "\n")

    @Test func stringIsTitleThenBlocksInOrder() {
        #expect(SummaryRichText.attributed(title: Self.title, blocks: Self.blocks).string == Self.expected)
    }

    @Test func itemsAreIndentedByDepth() throws {
        let text = try Self.readBack(SummaryRichText.rtf(title: Self.title, blocks: Self.blocks))
        let string = text.string as NSString
        for (line, depth) in [("• Existing", 0), ("• Harbour", 1), ("• Invoices", 2), ("1. Tomas", 0)] {
            let location = string.range(of: line).location
            try #require(location != NSNotFound, "\(line)")
            let style = try #require(text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
            #expect(style.headIndent == CGFloat(20 * depth), "\(line)")
            #expect(style.firstLineHeadIndent == CGFloat(20 * depth), "\(line)")
        }
    }

    @Test func rtfIsNonEmptyAndReadsBackToTheSameString() throws {
        let rtf = SummaryRichText.rtf(title: Self.title, blocks: Self.blocks)
        #expect(rtf.isEmpty == false)
        #expect(try Self.readBack(rtf).string == Self.expected)
    }

    @Test func linksAreNotCarried() throws {
        let blocks = SummaryDocument(markdown: """
            See [the index](https://example.com/index) and ![chart](https://example.com/chart.png).
            - <https://example.com/raw>
            """).blocks
        let text = try Self.readBack(SummaryRichText.rtf(title: Self.title, blocks: blocks))

        #expect(text.string == "Weekly platform sync\nSee the index and chart.\n• https://example.com/raw")
        var links = 0
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value != nil { links += 1 }
        }
        #expect(links == 0)
    }
}
