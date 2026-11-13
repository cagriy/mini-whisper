import SwiftUI

/// The results page (design §5.9, R19): matching meetings with their snippets, then matching
/// dictations, every occurrence of the query marked.
struct SearchPage: View {
    let model: MainWindowModel

    private var search: SearchModel { model.search }

    var body: some View {
        PageColumn("Results for \u{201C}\(model.query)\u{201D}") {
            if let error = model.openError { StatusLine(error, .warning) }
            if search.meetings.isEmpty, search.dictations.isEmpty {
                if !search.isSearching {
                    Text("No matches for \u{201C}\(model.query)\u{201D}")
                        .textStyle(.body)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: DS.Space.s1) {
                    if !search.meetings.isEmpty {
                        DayHeader("Meetings · \(search.meetings.count)")
                        ForEach(search.meetings) { meetingRow($0) }
                    }
                    if !search.dictations.isEmpty {
                        DayHeader("Dictations · \(search.dictations.count)")
                        ForEach(search.dictations) { dictationRow($0) }
                    }
                }
            }
        }
    }

    private func meetingRow(_ hit: SearchModel.MeetingHit) -> some View {
        ListRow(time: hit.time, activate: { Task { await model.openMeeting(hit.id) } }) {
            Tile(mode: hit.mode)
        } content: { _ in
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DS.Space.s4) {
                    Text(hit.title).lineLimit(1)
                    if hit.isTest { Chip("TEST", .test) }
                }
                .textStyle(.rowTitle)
                .foregroundStyle(DS.Colors.text)
                ForEach(Array(hit.snippets.enumerated()), id: \.offset) { _, snippet in
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                        Text(snippet.label)
                            .textStyle(DS.TextStyle.meta.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(DS.Colors.textTertiary)
                        Text(marked(snippet.text))
                            .textStyle(.body)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                }
                meta(hit.meta)
            }
        }
    }

    private func dictationRow(_ hit: SearchModel.DictationHit) -> some View {
        ListRow(activate: { model.navigation.revealDictation(hit.id) }) {
            Tile(glyph: hit.glyph)
        } content: { _ in
            VStack(alignment: .leading, spacing: 0) {
                Text(marked(hit.text))
                    .textStyle(.body)
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(2)
                meta(hit.meta)
            }
        }
    }

    private func meta(_ text: String) -> some View {
        Text(text)
            .textStyle(.meta)
            .monospacedDigit()
            .foregroundStyle(DS.Colors.textTertiary)
            .frame(minHeight: DS.Size.controlSmall, alignment: .leading)
    }

    private func marked(_ text: String) -> AttributedString {
        QueryHighlight.attributed(text, query: model.query)
    }
}

/// Marks the query in a result's text with the accent-soft fill, matched as search matches it.
enum QueryHighlight {
    static func matches(of query: String, in text: String) -> [Range<String.Index>] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var rest = text.startIndex..<text.endIndex
        while let match = text.range(of: needle, options: .caseInsensitive, range: rest) {
            found.append(match)
            rest = match.upperBound..<text.endIndex
        }
        return found
    }

    static func attributed(_ text: String, query: String) -> AttributedString {
        var marked = AttributedString(text)
        for match in matches(of: query, in: text) {
            // Both count the same characters, so an offset in one is an offset in the other.
            let start = marked.characters.index(
                marked.startIndex, offsetBy: text.distance(from: text.startIndex, to: match.lowerBound)
            )
            let end = marked.characters.index(start, offsetBy: text.distance(from: match.lowerBound, to: match.upperBound))
            marked[start..<end].backgroundColor = DS.Colors.accentSoft
        }
        return marked
    }
}
