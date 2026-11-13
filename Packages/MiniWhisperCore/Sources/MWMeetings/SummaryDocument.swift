import Foundation

/// A summary's Markdown as blocks. Line-based: what is not a heading, list item, rule or
/// fenced block stays paragraph text, tables and HTML included.
public struct SummaryDocument: Sendable, Equatable {
    public enum Block: Sendable, Equatable {
        /// `level` is 1...3.
        case heading(level: Int, text: String)
        case paragraph(String)
        /// `depth` is 0...3; `ordinal` is set for an ordered item. A continuation line follows a `\n`.
        case item(depth: Int, ordinal: Int?, text: String)
        case rule
        case code(String)
    }

    public let blocks: [Block]

    public init(markdown: String) {
        // The heading's text is cut by hand below: `(.*?)\s*#*$` backtracks quadratically over a
        // long run of `#` or spaces.
        let heading = /^ {0,3}(#{1,6})\s+/
        let rule = /^ {0,3}([-*_])(\s*\1){2,}\s*$/
        let unordered = /^(\s*)[-*+]\s+(.*)$/
        // ASCII digits only: `Int` reads no others.
        let ordered = /^(\s*)(\d{1,9})[.)]\s+(.*)$/.asciiOnlyDigits()

        var blocks: [Block] = []
        // Lines of the open fenced block.
        var fence: [String]?
        // Indents of the open list's levels, outermost first.
        var indents: [Int] = []
        var afterBlank = false

        func add(_ block: Block) {
            blocks.append(block)
            indents = []
            afterBlank = false
        }

        func addItem(indent: Substring, ordinal: Int?, text: Substring) {
            let columns = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            while let top = indents.last, top > columns { indents.removeLast() }
            if indents.last != columns { indents.append(columns) }
            blocks.append(.item(depth: min(indents.count - 1, 3), ordinal: ordinal, text: String(text)))
            afterBlank = false
        }

        func addText(_ line: String) {
            var text = Substring(line)
            if text.hasPrefix("> ") { text.removeFirst(2) }
            let indented = text.first?.isWhitespace == true
            let body = String(text.drop(while: \.isWhitespace))
            switch blocks.last {
            case .item(let depth, let ordinal, let item) where indented && !afterBlank:
                blocks[blocks.count - 1] = .item(depth: depth, ordinal: ordinal, text: item + "\n" + body)
            case .paragraph(let open) where !afterBlank:
                blocks[blocks.count - 1] = .paragraph(open + " " + body)
            default:
                add(.paragraph(body))
            }
        }

        for raw in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var line = String(raw)
            while line.last?.isWhitespace == true { line.removeLast() }
            let marksFence = line.drop(while: \.isWhitespace).hasPrefix("```")

            if fence != nil {
                if marksFence {
                    add(.code(fence?.joined(separator: "\n") ?? ""))
                    fence = nil
                } else {
                    fence?.append(line)
                }
            } else if marksFence {
                fence = []
            } else if let match = line.firstMatch(of: heading) {
                var text = line[match.range.upperBound...]
                while text.last == "#" { text.removeLast() }
                while text.last?.isWhitespace == true { text.removeLast() }
                add(.heading(level: min(match.1.count, 3), text: String(text)))
            } else if line.firstMatch(of: rule) != nil {
                add(.rule)
            } else if let match = line.firstMatch(of: unordered) {
                addItem(indent: match.1, ordinal: nil, text: match.2)
            } else if let match = line.firstMatch(of: ordered) {
                addItem(indent: match.1, ordinal: Int(match.2), text: match.3)
            } else if line.isEmpty {
                afterBlank = true
            } else {
                addText(line)
            }
        }
        if let fence { add(.code(fence.joined(separator: "\n"))) }
        self.blocks = blocks
    }

    // MARK: - Derived values

    /// The top-level headings, without `Next Steps`.
    public var topics: [String] {
        topLevelHeadings.filter { $0.lowercased() != "next steps" }
    }

    /// The format summaries had before they were organised by topic.
    public var isFourSection: Bool {
        let headings = Set(topLevelHeadings.map { $0.lowercased() })
        return headings.contains("summary") && headings.isSubset(of: Self.fourSections)
    }

    /// The index excerpt: the topics, or the first sentence where there are none to list.
    public static func excerpt(ofSummary markdown: String) -> String {
        let document = SummaryDocument(markdown: markdown)
        let topics = document.topics
        guard topics.isEmpty || document.isFourSection else { return topics.joined(separator: " · ") }
        for block in document.blocks {
            switch block {
            case .paragraph(let text), .item(_, _, let text):
                let plain = Self.plain(text)
                guard let end = plain.firstMatch(of: /[.!?](?=\s)/) else { return plain }
                return String(plain[..<end.range.upperBound])
            case .heading, .rule, .code:
                continue
            }
        }
        return ""
    }

    /// Inline Markdown. Links and images stay text: a summary is model output over untrusted speech.
    public static func inline(_ text: String) -> AttributedString {
        guard var parsed = try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return AttributedString(text) }
        parsed.link = nil
        parsed.imageURL = nil
        return parsed
    }

    /// Escaped text in a fixed set of tags, with no attribute.
    public func html(title: String) -> String {
        let levels = Set(blocks.compactMap { block -> Int? in
            if case .heading(let level, _) = block { level } else { nil }
        }).sorted()
        var parts = ["<h1>\(Self.escaped(title))</h1>"]
        var list = ""
        // Tags of the open lists, outermost first; each has an open `<li>`.
        var open: [String] = []

        func close(to count: Int) {
            while open.count > count { list += "</li></\(open.removeLast())>" }
        }

        func endList() {
            close(to: 0)
            if !list.isEmpty { parts.append(list) }
            list = ""
        }

        for block in blocks {
            if case .item = block {} else { endList() }
            switch block {
            case .heading(let level, let text):
                let tag = "h\(2 + (levels.firstIndex(of: level) ?? 0))"
                parts.append("<\(tag)>\(Self.inlineHTML(text))</\(tag)>")
            case .paragraph(let text):
                parts.append("<p>\(Self.inlineHTML(text))</p>")
            case .item(let depth, let ordinal, let text):
                let tag = ordinal == nil ? "ul" : "ol"
                close(to: depth + 1)
                if open.count == depth + 1, open[depth] != tag { close(to: depth) }
                if open.count == depth + 1 { list += "</li><li>" }
                while open.count <= depth {
                    open.append(tag)
                    list += "<\(tag)><li>"
                }
                list += Self.inlineHTML(text)
            case .rule:
                parts.append("<hr>")
            case .code(let text):
                parts.append("<pre>\(Self.escaped(text))</pre>")
            }
        }
        endList()
        return parts.joined(separator: "\n")
    }

    /// The stored summary under its title, not re-serialised from the blocks.
    public static func markdown(title: String, summary: String) -> String {
        "# " + title + "\n\n" + summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internals

    private static let fourSections: Set<String> = ["summary", "decisions", "action items", "open questions"]

    /// Innermost first.
    private static let inlineTags: [(intent: InlinePresentationIntent, tag: String)] = [
        (.code, "code"), (.strikethrough, "s"), (.emphasized, "em"), (.stronglyEmphasized, "strong"),
    ]

    /// The plain text of each heading at the smallest level present.
    private var topLevelHeadings: [String] {
        let headings = blocks.compactMap { block -> (level: Int, text: String)? in
            if case .heading(let level, let text) = block { (level, text) } else { nil }
        }
        guard let top = headings.map(\.level).min() else { return [] }
        return headings.filter { $0.level == top }.map { Self.plain($0.text) }
    }

    private static func plain(_ text: String) -> String {
        String(inline(text).characters)
    }

    private static func inlineHTML(_ text: String) -> String {
        let attributed = inline(text)
        return attributed.runs.map { run in
            let intent = run.inlinePresentationIntent ?? []
            let text = escaped(String(attributed[run.range].characters)).replacingOccurrences(of: "\n", with: "<br>")
            return inlineTags.reduce(text) { html, entry in
                intent.contains(entry.intent) ? "<\(entry.tag)>\(html)</\(entry.tag)>" : html
            }
        }.joined()
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
