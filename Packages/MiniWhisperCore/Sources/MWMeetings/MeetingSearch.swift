import Foundation

/// One labelled excerpt around a match.
public struct SearchSnippet: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case transcript, note, summary
    }

    public var source: Source
    /// Meeting seconds; `nil` for the summary.
    public var time: Double?
    public var text: String

    public init(source: Source, time: Double?, text: String) {
        self.source = source
        self.time = time
        self.text = text
    }
}

/// A matching meeting; a match in the title alone carries no snippets.
public struct SearchHit: Codable, Sendable, Equatable {
    public var meetingID: UUID
    public var snippets: [SearchSnippet]

    public init(meetingID: UUID, snippets: [SearchSnippet]) {
        self.meetingID = meetingID
        self.snippets = snippets
    }
}

/// Case-insensitive substring search over titles, transcripts, notes and summaries.
public struct MeetingSearch: Sendable {
    private static let snippetsPerMeeting = 2
    /// Characters of context kept on each side of a match.
    private static let context = 40

    public init() {}

    /// Hits in the order of `meetings`; snippets transcript, then notes, then summary, each by time.
    public func search(_ query: String, in meetings: [LoadedMeeting]) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return meetings.compactMap { loaded in
            let snippets = snippets(for: needle, in: loaded)
            guard !snippets.isEmpty || loaded.meeting.title.range(of: needle, options: .caseInsensitive) != nil
            else { return nil }
            return SearchHit(meetingID: loaded.meeting.id, snippets: snippets)
        }
    }

    private func snippets(for needle: String, in loaded: LoadedMeeting) -> [SearchSnippet] {
        var found: [SearchSnippet] = []
        func scan(_ source: SearchSnippet.Source, _ entries: [(time: Double?, text: String)]) {
            for entry in entries where found.count < Self.snippetsPerMeeting {
                if let text = excerpt(entry.text, around: needle) {
                    found.append(SearchSnippet(source: source, time: entry.time, text: text))
                }
            }
        }
        scan(.transcript, loaded.segments.sorted { $0.start < $1.start }.map { ($0.start, $0.text) })
        scan(.note, loaded.notes.sorted { $0.time < $1.time }.map { ($0.time, $0.text) })
        let summary = loaded.meeting.summary?.text.components(separatedBy: .newlines) ?? []
        scan(.summary, summary.filter { !$0.hasPrefix("#") }.map { (nil, Self.plain($0)) })
        return found
    }

    /// A summary line without its list marker and bold markers.
    private static func plain(_ line: String) -> String {
        var text = line.replacingOccurrences(of: "**", with: "")
        if text.hasPrefix("- ") { text.removeFirst(2) }
        return text
    }

    /// About `context` characters either side of the first match, cut at word boundaries, on one line.
    private func excerpt(_ text: String, around needle: String) -> String? {
        guard let match = text.range(of: needle, options: .caseInsensitive) else { return nil }
        var lower = text.index(match.lowerBound, offsetBy: -Self.context, limitedBy: text.startIndex) ?? text.startIndex
        var upper = text.index(match.upperBound, offsetBy: Self.context, limitedBy: text.endIndex) ?? text.endIndex
        if lower > text.startIndex, !text[text.index(before: lower)].isWhitespace,
           let space = text[lower..<match.lowerBound].firstIndex(where: \.isWhitespace) {
            lower = text.index(after: space)
        }
        if upper < text.endIndex, !text[upper].isWhitespace,
           let space = text[match.upperBound..<upper].lastIndex(where: \.isWhitespace) {
            upper = space
        }
        let cut = text[lower..<upper].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (lower > text.startIndex ? "…" : "") + cut + (upper < text.endIndex ? "…" : "")
    }
}
