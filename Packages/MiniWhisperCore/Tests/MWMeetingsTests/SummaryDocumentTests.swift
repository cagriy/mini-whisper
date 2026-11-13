import Foundation
import MWTestSupport
import Testing

import MWMeetings

@Suite struct SummaryDocumentTests {
    private typealias Block = SummaryDocument.Block

    private let topicText = MeetingFixtures.topicSummary().text
    private let fourSectionText = MeetingFixtures.northwind().meeting.summary?.text ?? ""

    private func blocks(_ markdown: String) -> [Block] {
        SummaryDocument(markdown: markdown).blocks
    }

    private func item(_ text: String, depth: Int = 0, ordinal: Int? = nil) -> Block {
        .item(depth: depth, ordinal: ordinal, text: text)
    }

    private func depths(_ markdown: String) -> [Int] {
        blocks(markdown).compactMap { block -> Int? in
            if case .item(let depth, _, _) = block { depth } else { nil }
        }
    }

    private func html(_ markdown: String, title: String = "T") -> String {
        SummaryDocument(markdown: markdown).html(title: title)
    }

    // MARK: - Parsing rules

    @Test func fencedCodeKeepsItsLinesVerbatim() {
        let markdown = """
            Before
            ```swift
            ## not a heading
              - not an item

            > not a quote
            ```
            After
            """
        #expect(blocks(markdown) == [
            .paragraph("Before"),
            .code("## not a heading\n  - not an item\n\n> not a quote"),
            .paragraph("After"),
        ])
    }

    @Test func unclosedFenceRunsToTheEnd() {
        #expect(blocks("Intro\n  ```\ncode\n\n- still code") == [
            .paragraph("Intro"),
            .code("code\n\n- still code"),
        ])
        #expect(blocks("```") == [.code("")])
    }

    @Test func headingsCapTheirLevelAtThreeAndDropClosingHashes() {
        #expect(blocks("# One\n## Two ##\n### Three\n###### Six\n   ## Indented\n## C# ##\n## Budget #3") == [
            .heading(level: 1, text: "One"),
            .heading(level: 2, text: "Two"),
            .heading(level: 3, text: "Three"),
            .heading(level: 3, text: "Six"),
            .heading(level: 2, text: "Indented"),
            .heading(level: 2, text: "C#"),
            .heading(level: 2, text: "Budget #3"),
        ])
    }

    @Test func hashesWithoutASpaceOrPastSixAreText() {
        #expect(blocks("#NoSpace") == [.paragraph("#NoSpace")])
        #expect(blocks("####### Seven") == [.paragraph("####### Seven")])
        #expect(blocks("    ## Four spaces in") == [.paragraph("## Four spaces in")])
    }

    @Test func threeOrMoreDashesStarsOrUnderscoresAreARule() {
        #expect(blocks("---\n***\n___\n - - -\n*****") == [.rule, .rule, .rule, .rule, .rule])
        #expect(blocks("--") == [.paragraph("--")])
        #expect(blocks("-*-") == [.paragraph("-*-")])
    }

    @Test func unorderedItemsTakeADashStarOrPlus() {
        #expect(blocks("- dash\n* star\n+ plus\n-   spaced") == [
            item("dash"), item("star"), item("plus"), item("spaced"),
        ])
        #expect(blocks("-no space") == [.paragraph("-no space")])
    }

    @Test func orderedItemsKeepTheirOrdinal() {
        #expect(blocks("1. one\n2) two\n10. ten") == [
            item("one", ordinal: 1), item("two", ordinal: 2), item("ten", ordinal: 10),
        ])
        #expect(blocks("1234567890. ten digits") == [.paragraph("1234567890. ten digits")])
        #expect(blocks("1.5 million") == [.paragraph("1.5 million")])
        #expect(blocks("١. one") == [.paragraph("١. one")])
    }

    @Test func blankLineEndsTheParagraphAndMakesNoBlock() {
        #expect(blocks("one\ntwo\n\n\nthree") == [.paragraph("one two"), .paragraph("three")])
        #expect(blocks(" \n\n\t\nfour\n \n") == [.paragraph("four")])
        #expect(blocks("").isEmpty)
        #expect(blocks(" \n\n\t").isEmpty)
    }

    @Test func indentedLineContinuesTheItemAbove() {
        #expect(blocks("- first\n  more\n\tand more\n- second") == [
            item("first\nmore\nand more"), item("second"),
        ])
    }

    @Test func unindentedOrSeparatedLineAfterAnItemIsAParagraph() {
        #expect(blocks("- first\nnot indented\nnext") == [item("first"), .paragraph("not indented next")])
        #expect(blocks("- first\n\n  after a blank") == [item("first"), .paragraph("after a blank")])
    }

    @Test func quoteMarkerIsStripped() {
        #expect(blocks("> quoted\n> more\n\n> again") == [.paragraph("quoted more"), .paragraph("again")])
    }

    @Test func tablesAndHTMLStayParagraphText() {
        #expect(blocks("| a | b |\n|---|---|\n| 1 | 2 |") == [.paragraph("| a | b | |---|---| | 1 | 2 |")])
        #expect(blocks("<div>hi</div>\n<img src=x>") == [.paragraph("<div>hi</div> <img src=x>")])
    }

    @Test func lineEndingsAndTrailingWhitespaceAreNormalised() {
        #expect(blocks("## Title  \r\none\t\rtwo\r\n\r\n- item \r\n") == [
            .heading(level: 2, text: "Title"),
            .paragraph("one two"),
            item("item"),
        ])
    }

    // A summary can be some 64,000 characters, all on one line.
    @Test(.timeLimit(.minutes(1))) func aLongRunOfHashesOrSpacesParsesInLinearTime() {
        let hashes = String(repeating: "#", count: 64_000)
        let spaces = String(repeating: " ", count: 64_000)

        #expect(blocks("## \(hashes)x") == [.heading(level: 2, text: "\(hashes)x")])
        #expect(blocks("## a\(spaces)x \(hashes)") == [.heading(level: 2, text: "a\(spaces)x")])
        #expect(blocks("-\(spaces)- -\(spaces)x") == [item("- -\(spaces)x")])
        #expect(blocks("\(spaces)x") == [.paragraph("x")])
    }

    @Test func topicSummaryParsesIntoHeadingsAndNestedItems() {
        #expect(Array(blocks(topicText).prefix(5)) == [
            .heading(level: 2, text: "Northwind rollout"),
            item("The rollout slips a week unless the migration script is signed off."),
            item("Sign-off moves from Thursday to Wednesday, leaving a day of slack.", depth: 1),
            item("**Priya** refreshes staging data tonight: the last snapshot is from October."),
            .heading(level: 2, text: "Enterprise pricing"),
        ])
    }

    // MARK: - Item depth

    @Test func twoSpaceNestingDeepensByOne() {
        #expect(depths("- a\n  - b\n    - c\n  - d\n- e") == [0, 1, 2, 1, 0])
    }

    @Test func fourSpaceNestingDeepensByOne() {
        #expect(depths("1. a\n    - b\n        - c\n2. d") == [0, 1, 2, 0])
    }

    @Test func tabCountsAsFourColumns() {
        #expect(depths("- a\n\t- b\n\t\t- c\n    - d") == [0, 1, 2, 1])
    }

    @Test func depthIsCappedAtThree() {
        #expect(depths("- a\n  - b\n    - c\n      - d\n        - e\n          - f\n- g") == [0, 1, 2, 3, 3, 3, 0])
    }

    @Test func dedentToAnUnseenIndentNestsUnderTheNearestShallowerItem() {
        #expect(depths("- a\n    - b\n  - c") == [0, 1, 1])
        #expect(depths("  - a\n- b") == [0, 0])
    }

    @Test func blankLineKeepsTheDepthAndAnyOtherBlockResetsIt() {
        #expect(depths("- a\n  - b\n\n  - c") == [0, 1, 1])
        #expect(depths("- a\n  - b\n\nText\n\n  - c") == [0, 1, 0])
        #expect(depths("- a\n  - b\n## Heading\n  - c") == [0, 1, 0])
        #expect(depths("- a\n  - b\n---\n  - c") == [0, 1, 0])
        #expect(depths("- a\n  - b\n```\ncode\n```\n  - c") == [0, 1, 0])
    }

    // MARK: - Derived values

    @Test func topicsAreTheTopLevelHeadingsExceptNextSteps() {
        #expect(SummaryDocument(markdown: topicText).topics == ["Northwind rollout", "Enterprise pricing", "Demo date"])
        #expect(SummaryDocument(markdown: "## A\n### Sub\n## NEXT steps\n## **C** and `d`").topics == ["A", "C and d"])
        #expect(SummaryDocument(markdown: "Only text.\n\n- item").topics.isEmpty)
    }

    @Test func topLevelIsTheSmallestHeadingLevelPresent() {
        #expect(SummaryDocument(markdown: "# Title\n## A\n## B").topics == ["Title"])
        #expect(SummaryDocument(markdown: "### A\n### B").topics == ["A", "B"])
    }

    @Test func fourSectionMeansOnlyTheFourFixedHeadingsWithSummaryAmongThem() {
        #expect(SummaryDocument(markdown: fourSectionText).isFourSection)
        #expect(SummaryDocument(markdown: "## SUMMARY\n\nText.\n\n### Detail\n\n## open questions\n\n- None.").isFourSection)
        #expect(SummaryDocument(markdown: topicText).isFourSection == false)
        #expect(SummaryDocument(markdown: "## Decisions\n\n- One.").isFourSection == false)
        #expect(SummaryDocument(markdown: "## Summary\n\nText.\n\n## Risks\n\n- One.").isFourSection == false)
        #expect(SummaryDocument(markdown: "Text only.").isFourSection == false)
    }

    @Test func excerptOfATopicSummaryJoinsItsTopics() {
        #expect(SummaryDocument.excerpt(ofSummary: topicText) == "Northwind rollout · Enterprise pricing · Demo date")
    }

    @Test func excerptOfAFourSectionSummaryIsItsFirstSentence() {
        #expect(SummaryDocument.excerpt(ofSummary: fourSectionText) == """
            The Northwind rollout stays on schedule provided the migration script is reviewed by \
            Wednesday, after Priya refreshes staging data tonight.
            """)
        #expect(SummaryDocument.excerpt(ofSummary: "## Summary\n\n- **Marta** owns the script! More.") == "Marta owns the script!")
    }

    @Test func excerptWithoutTopicsIsTheFirstSentenceOfTheFirstParagraphOrItem() {
        #expect(SummaryDocument.excerpt(ofSummary: "Short call?\nNothing was decided.") == "Short call?")
        #expect(SummaryDocument.excerpt(ofSummary: "---\n- Version 1.5 shipped, it's live") == "Version 1.5 shipped, it's live")
        #expect(SummaryDocument.excerpt(ofSummary: "## Next Steps\n\n- **Priya**: refresh staging. Tonight.") == "Priya: refresh staging.")
        #expect(SummaryDocument.excerpt(ofSummary: "") == "")
        #expect(SummaryDocument.excerpt(ofSummary: " \n\n") == "")
        #expect(SummaryDocument.excerpt(ofSummary: "```\ncode only\n```") == "")
    }

    // MARK: - Inline

    @Test func inlineDropsLinksAndImagesAndKeepsTheirText() {
        let text = SummaryDocument.inline(
            "See [the doc](https://example.com/doc), ![a chart](https://example.com/chart.png) and https://example.com/bare."
        )

        #expect(String(text.characters) == "See the doc, a chart and https://example.com/bare.")
        #expect(text.runs.allSatisfy { $0.link == nil && $0.imageURL == nil })
    }

    @Test func inlineKeepsBoldItalicStrikethroughAndCode() {
        let text = SummaryDocument.inline("**bold** _italic_ ~~gone~~ `code` plain\n  next")
        func has(_ intent: InlinePresentationIntent) -> Bool {
            text.runs.contains { $0.inlinePresentationIntent?.contains(intent) == true }
        }

        #expect(String(text.characters) == "bold italic gone code plain\n  next")
        #expect(has(.stronglyEmphasized))
        #expect(has(.emphasized))
        #expect(has(.strikethrough))
        #expect(has(.code))
    }

    // MARK: - HTML

    @Test func htmlEscapesEveryTextNode() {
        let markdown = """
            ## R&D <team> "A"

            Tom & Ann: a < b > c, "quoted".

            - x < y & "z"

            ```
            if a < b && c > "d" {}
            ```
            """

        #expect(html(markdown, title: "Q&A <1> \"x\"") == """
            <h1>Q&amp;A &lt;1&gt; &quot;x&quot;</h1>
            <h2>R&amp;D &lt;team&gt; &quot;A&quot;</h2>
            <p>Tom &amp; Ann: a &lt; b &gt; c, &quot;quoted&quot;.</p>
            <ul><li>x &lt; y &amp; &quot;z&quot;</li></ul>
            <pre>if a &lt; b &amp;&amp; c &gt; &quot;d&quot; {}</pre>
            """)
    }

    @Test func htmlNestsListsByDepth() {
        let markdown = "- a\n  - b\n    1. c\n    2. d\n  - e\n- f\n\n1. g\n   more\n\nEnd"

        #expect(html(markdown) == """
            <h1>T</h1>
            <ul><li>a<ul><li>b<ol><li>c</li><li>d</li></ol></li><li>e</li></ul></li><li>f</li></ul>\
            <ol><li>g<br>more</li></ol>
            <p>End</p>
            """)
    }

    @Test func htmlMapsTheHeadingLevelsPresentToH2H3H4() {
        #expect(html("# A\n## B\n### C") == "<h1>T</h1>\n<h2>A</h2>\n<h3>B</h3>\n<h4>C</h4>")
        #expect(html("## A\n### B\n## C") == "<h1>T</h1>\n<h2>A</h2>\n<h3>B</h3>\n<h2>C</h2>")
        #expect(html("### A\n# B") == "<h1>T</h1>\n<h3>A</h3>\n<h2>B</h2>")
    }

    @Test func htmlRendersRulesCodeAndInlineStyles() {
        let rendered = html("**bold** _italic_ ~~gone~~ `code`\n\n---\n\n```\nline 1\n  line 2\n```")

        #expect(rendered.contains("<strong>bold</strong>"))
        #expect(rendered.contains("<em>italic</em>"))
        #expect(rendered.contains("<s>gone</s>"))
        #expect(rendered.contains("<code>code</code>"))
        #expect(rendered.hasPrefix("<h1>T</h1>\n<p>"))
        #expect(rendered.hasSuffix("</p>\n<hr>\n<pre>line 1\n  line 2</pre>"))
    }

    @Test func htmlNeverEmitsALinkAnImageAScriptOrAnAttribute() {
        let markdown = """
            ## <script>alert(1)</script>

            [click](https://example.com/doc) ![pixel](https://example.com/p.png) \
            <a href="https://example.org">here</a> <img src=x onerror=alert(1)>

            - <script src="x"></script>
              <b onclick="y">bold</b>

            ```
            <a href="z">in code</a>
            ```
            """
        let rendered = html(markdown, title: "<img src=x>")
        let allowed = Set(
            ["h1", "h2", "h3", "h4", "p", "ul", "ol", "li", "pre", "strong", "em", "s", "code"]
                .flatMap { ["<\($0)>", "</\($0)>"] } + ["<br>", "<hr>"]
        )

        #expect(rendered.matches(of: /<[^>]*>/).allSatisfy { allowed.contains(String($0.output)) })
        #expect(rendered.contains("<a") == false)
        #expect(rendered.contains("<img") == false)
        #expect(rendered.contains("<script") == false)
        #expect(rendered.contains("example.com") == false)
        #expect(rendered.contains("click pixel"))
        #expect(rendered.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
    }

    @Test func htmlOfTheTopicSummaryNestsItsSecondLevelBullets() {
        let rendered = SummaryDocument(markdown: topicText).html(title: "Northwind rollout sync")

        #expect(rendered.hasPrefix("""
            <h1>Northwind rollout sync</h1>
            <h2>Northwind rollout</h2>
            <ul><li>The rollout slips a week unless the migration script is signed off.\
            <ul><li>Sign-off moves from Thursday to Wednesday, leaving a day of slack.</li></ul></li>\
            <li><strong>Priya</strong> refreshes staging data tonight: the last snapshot is from October.</li></ul>
            <h2>Enterprise pricing</h2>
            """))
        #expect(rendered.contains("<h2>Next Steps</h2>\n<ul><li><strong>Priya</strong>: refresh staging data tonight.</li>"))
    }

    // MARK: - Markdown

    @Test func markdownIsTheTitleThenTheTrimmedSummary() {
        #expect(SummaryDocument.markdown(title: "Sync", summary: "\n\n## A\n\n- b  \n\n") == "# Sync\n\n## A\n\n- b")
        #expect(SummaryDocument.markdown(title: "Northwind rollout sync", summary: topicText)
            == "# Northwind rollout sync\n\n" + topicText)
    }
}
