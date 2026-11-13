import AppKit

/// Copy summary's write: the Markdown as plain text, beside HTML and RTF for apps that take
/// rich text (R17).
@MainActor
enum RichPasteboardWriting {
    static func write(markdown: String, html: String, rtf: Data, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .html, .rtf], owner: nil)
        pasteboard.setString(markdown, forType: .string)
        pasteboard.setString(html, forType: .html)
        pasteboard.setData(rtf, forType: .rtf)
    }
}
