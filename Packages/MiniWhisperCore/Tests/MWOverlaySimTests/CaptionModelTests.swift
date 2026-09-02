import Foundation
import Testing

import MWOverlaySim

/// The caption bar's pure line composition — a port of `wrap_caption`, `caption_lines` and
/// `with_unavailable` in `../mini-whisper/src/mini_whisper/overlay.py` and of
/// `tests/test_caption_bar.py` (design §5.6).
@Suite struct CaptionModelTests {
    /// Seven points per character, so the 448 pt usable width fits exactly 64 characters.
    private let measure: (String) -> Double = { Double($0.count) * 7 }

    private func words(_ count: Int, _ word: String = "abcde") -> String {
        Array(repeating: word, count: count).joined(separator: " ")
    }

    @Test func wrapsAgainst448ptUsableWidth() {
        #expect(Constants.captionWidth - 2 * Constants.captionPaddingH == 448)

        let lines = CaptionModel.lines(text: words(20), dimmed: false, measure: measure)

        // Ten five-letter words are 59 characters (413 pt); an eleventh would be 455 pt.
        #expect(lines.map(\.text) == [words(10), words(10)])
    }

    @Test func keepsOnlyLastSevenLines() {
        let lines = CaptionModel.lines(text: words(400), dimmed: false, measure: measure)

        #expect(lines.count == Constants.captionMaxLines)
    }

    @Test func olderLinesDimCurrentBright() {
        let single = CaptionModel.lines(text: "one two", dimmed: false, measure: measure)
        #expect(single == [CaptionLine(text: "one two", alpha: Constants.captionCurrentAlpha)])

        let wrapped = CaptionModel.lines(text: words(20), dimmed: false, measure: measure)
        #expect(wrapped.map(\.alpha) == [Constants.captionOlderAlpha, Constants.captionCurrentAlpha])
    }

    @Test func dimmedUsesProcessingAlphas() {
        let single = CaptionModel.lines(text: "one two", dimmed: true, measure: measure)
        #expect(single == [CaptionLine(text: "one two", alpha: Constants.captionDimmedAlpha)])

        let wrapped = CaptionModel.lines(text: words(20), dimmed: true, measure: measure)
        #expect(wrapped.map(\.alpha) == [
            Constants.captionDimmedOlderAlpha, Constants.captionDimmedAlpha,
        ])
    }

    @Test func unavailableKeepsTranscribedText() {
        let lines = CaptionModel.lines(text: "hello world", dimmed: true, measure: measure)

        let withWarning = CaptionModel.withUnavailable(lines)

        #expect(withWarning.first?.text == "hello world")
        #expect(withWarning.last == CaptionLine(
            text: Constants.captionUnavailableText, alpha: Constants.captionCurrentAlpha
        ))
    }

    @Test func unavailableAloneWhenNothingTranscribed() {
        #expect(CaptionModel.withUnavailable([]) == [CaptionLine(
            text: Constants.captionUnavailableText, alpha: Constants.captionCurrentAlpha
        )])
    }

    @Test func unavailableNotAppendedTwice() {
        let once = CaptionModel.withUnavailable(
            CaptionModel.lines(text: "hello", dimmed: true, measure: measure)
        )

        #expect(CaptionModel.withUnavailable(once) == once)
    }

    // The bottom row's entry animation belongs to a genuinely new line. A live partial
    // extends the current line word by word, and replaying the 120 ms fade on every word
    // is what made the caption flicker as if rewritten per word.

    @Test func growingLineIsNotANewLine() {
        #expect(!CaptionModel.isNewLine(previous: "hello", current: "hello world"))
        #expect(!CaptionModel.isNewLine(previous: "hello world", current: "hello world how"))
    }

    @Test func firstTextIsANewLine() {
        #expect(CaptionModel.isNewLine(previous: "", current: "hello"))
    }

    @Test func wrappedLineIsANewLine() {
        #expect(CaptionModel.isNewLine(previous: "the end of a long line", current: "next"))
    }

    @Test func backtrackingRevisionIsNotANewLine() {
        // The restart heuristic can shorten the live partial; that is the same line
        // being revised, not a new one.
        #expect(!CaptionModel.isNewLine(previous: "hello world", current: "hello"))
    }

    @Test func clearingIsNotANewLine() {
        #expect(!CaptionModel.isNewLine(previous: "hello", current: ""))
        #expect(!CaptionModel.isNewLine(previous: "", current: ""))
    }
}
