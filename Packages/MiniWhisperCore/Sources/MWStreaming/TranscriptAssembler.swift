import Foundation

/// `CompoundTranscript` from `../mini-whisper/src/mini_whisper/streaming/base.py`:
/// finalised segments joined by single spaces plus the trailing partial (F22).
public struct TranscriptAssembler: Sendable, Equatable {
    private var finals: [String] = []
    private var partial = ""

    public init() {}

    public mutating func addPartial(_ text: String) {
        if Self.isSegmentRestart(old: partial, new: text) {
            finals.append(partial.trimmed)
        }
        partial = text
    }

    public mutating func addFinal(_ text: String) {
        let segment = text.trimmed
        guard !segment.isEmpty else { return }  // nothing finalised — keep the live partial
        finals.append(segment)
        partial = ""
    }

    public var text: String {
        var parts = finals
        let trailing = partial.trimmed
        if !trailing.isEmpty { parts.append(trailing) }
        return parts.joined(separator: " ")
    }

    /// True when `new` cannot be a revision of `old` — a fresh segment began.
    ///
    /// Engines (Apple's on-device recogniser in particular) can start a new segment
    /// without ever emitting a final, replacing a whole sentence with the first word
    /// of the next one. Growth, backtracking and tail revisions within one segment
    /// must not be mistaken for that.
    private static func isSegmentRestart(old: String, new: String) -> Bool {
        guard !old.trimmed.isEmpty else { return false }
        let oldFolded = old.lowercased()
        let newFolded = new.lowercased()
        // Growth or backtrack inside the segment.
        if newFolded.hasPrefix(oldFolded) || oldFolded.hasPrefix(newFolded) { return false }
        let oldWords = oldFolded.split(whereSeparator: \.isWhitespace)
        let newWords = newFolded.split(whereSeparator: \.isWhitespace)
        // Revised tail of the same segment.
        if let first = oldWords.first, first == newWords.first { return false }
        return newWords.count < oldWords.count
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
