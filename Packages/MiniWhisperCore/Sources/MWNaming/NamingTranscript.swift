import Foundation
import MWMeetings

/// Consecutive segments of one speaker.
public struct Turn: Sendable, Equatable {
    public struct Span: Sendable, Equatable {
        /// `Segment.id`.
        public let id: UUID
        public let start: Double
        /// Where the segment's text sits in `Turn.text`.
        public let range: Range<String.Index>
    }

    /// Counts every turn of the meeting from 1, including any dropped for length.
    public let number: Int
    public let speaker: Int
    public let segments: [Span]
    /// The segments' text joined by spaces, unescaped, so evidence quotes the stored transcript.
    public let text: String
}

public struct Rendered: Sendable, Equatable {
    public let turns: [Turn]
    public let blocks: [String]
    /// `blocks[0..<closedBlocks]`: appending segments leaves them byte-identical, so they can be cached.
    public let closedBlocks: Int
}

/// The meeting as numbered `S<id>` turns in 5-minute blocks.
public enum NamingTranscript {
    private static let blockSeconds = 300
    /// About 100K tokens, where the long-prompt rates start.
    private static let characterLimit = 400_000
    private static let omittedLine = "(earlier turns omitted)"

    public static func render(segments: [Segment]) -> Rendered {
        var groups: [[Segment]] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if groups.last?.first?.speaker == segment.speaker {
                groups[groups.count - 1].append(segment)
            } else {
                groups.append([segment])
            }
        }
        let all = groups.enumerated().map { turn(number: $0.offset + 1, of: $0.element) }
        let lines = all.map(line)

        // The newest turn stays even alone over the limit, so a request always has a transcript.
        var characters = lines.reduce(0) { $0 + $1.count + 1 }
        var dropped = 0
        while characters > characterLimit, dropped < lines.count - 1 {
            characters -= lines[dropped].count + 1
            dropped += 1
        }
        let turns = Array(all[dropped...])

        var windows: [[String]] = []
        var window: Int?
        for (turn, line) in zip(turns, lines[dropped...]) {
            let index = seconds(turn) / blockSeconds
            if index != window {
                windows.append([])
                window = index
            }
            windows[windows.count - 1].append(line + "\n")
        }
        if dropped > 0 { windows[0].insert(omittedLine + "\n", at: 0) }

        let blocks = windows.enumerated().map { index, lines in
            (index == 0 ? "<transcript>\n" : "") + lines.joined() + (index == windows.count - 1 ? "</transcript>" : "")
        }
        return Rendered(turns: turns, blocks: blocks, closedBlocks: max(blocks.count - 1, 0))
    }

    private static func turn(number: Int, of segments: [Segment]) -> Turn {
        let text = segments.map(\.text).joined(separator: " ")
        var lower = text.startIndex
        let spans = segments.map { segment in
            let upper = text.utf8.index(lower, offsetBy: segment.text.utf8.count)
            defer { if upper < text.endIndex { lower = text.utf8.index(after: upper) } }
            return Turn.Span(id: segment.id, start: segment.start, range: lower..<upper)
        }
        return Turn(number: number, speaker: segments[0].speaker, segments: spans, text: text)
    }

    private static func line(_ turn: Turn) -> String {
        let start = seconds(turn)
        let time = String(format: "%02d:%02d", start / 60, start % 60)
        return "T\(turn.number) S\(turn.speaker) [\(time)]: "
            + MeetingTextEscaping.escaped(turn.text, closing: "transcript")
    }

    private static func seconds(_ turn: Turn) -> Int {
        let start = turn.segments[0].start
        return start.isFinite ? max(0, Int(start)) : 0
    }
}
