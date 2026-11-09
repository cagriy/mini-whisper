import Foundation

public enum MeetingMarkdownError: Error, Equatable, LocalizedError {
    case noSummary

    public var errorDescription: String? {
        switch self {
        case .noSummary: "This meeting has no summary."
        }
    }
}

/// Meeting seconds as `hh:mm:ss` from Start.
public enum MeetingTime {
    public static func format(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}

/// The transcript and summary exports (design §5.4).
public enum MeetingMarkdown {
    public static func transcript(_ m: LoadedMeeting, generator: String, timeZone: TimeZone = .current) -> String {
        let meeting = m.meeting
        let front = frontMatter(m, timeZone: timeZone, fields: [
            ("engine", yaml(meeting.engine.title)),
            ("speakers", speakerList(m)),
            ("generator", yaml(generator)),
        ])
        let blocks = [front, "# \(meeting.title)", metaLine(m, timeZone: timeZone), "## Transcript"]
            + transcriptBlocks(m, withNotes: true)
        return blocks.joined(separator: "\n\n") + "\n"
    }

    public static func summary(_ m: LoadedMeeting, generator: String, timeZone: TimeZone = .current) throws -> String {
        guard let summary = m.meeting.summary else { throw MeetingMarkdownError.noSummary }
        let meeting = m.meeting
        let transcriptFile = TitleSanitizer.transcriptFileName(meeting.title)
        let front = frontMatter(m, timeZone: timeZone, fields: [
            ("speakers", speakerList(m)),
            ("summary_model", yaml(summary.model)),
            ("summary_at", utcTimestamp(summary.createdAt)),
            ("transcript", yaml(transcriptFile)),
            ("generator", yaml(generator)),
        ])
        var blocks = [
            front, "# \(meeting.title)", metaLine(m, timeZone: timeZone),
            summary.text.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if !m.notes.isEmpty {
            let list = m.notes.sorted { $0.time < $1.time }.map { "- \(MeetingTime.format($0.time)) · \(indented($0.text, by: "  "))" }
            blocks += ["## Notes", list.joined(separator: "\n")]
        }
        let minutes = Int(meeting.durationSeconds / 60)
        let footer = "Summary by \(modelName(summary.model)) at \(format(summary.createdAt, "HH:mm", timeZone)) "
            + "from \(plural(minutes, "minute")) of transcript and \(plural(m.notes.count, "note")) · "
            + "transcript: \(transcriptFile)"
        blocks += ["---", footer]
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// The transcript section without notes: what the summariser reads as transcript.
    public static func transcriptBody(_ m: LoadedMeeting) -> String {
        transcriptBlocks(m, withNotes: false).joined(separator: "\n\n")
    }

    // MARK: - Transcript section

    private enum Item {
        case segment(Segment)
        case note(Note)
        case marker(Marker)
    }

    private static func transcriptBlocks(_ m: LoadedMeeting, withNotes: Bool) -> [String] {
        var items: [(time: Double, item: Item)] = m.meeting.markers.map { ($0.start, .marker($0)) }
        if withNotes { items += m.notes.map { ($0.time, .note($0)) } }
        items += m.segments.map { ($0.start, .segment($0)) }
        // Stable sort: at equal times markers come first, then notes, then segments.
        let ordered = items.sorted { $0.time < $1.time }.map(\.item)

        var blocks: [String] = []
        var paragraph: (speaker: Int, start: Double, texts: [String])?
        func closeParagraph() {
            guard let open = paragraph else { return }
            blocks.append("**\(name(of: open.speaker, in: m))** · \(MeetingTime.format(open.start))\n"
                + open.texts.joined(separator: " "))
            paragraph = nil
        }
        for item in ordered {
            switch item {
            case .segment(let segment):
                if paragraph?.speaker == segment.speaker {
                    paragraph?.texts.append(segment.text)
                } else {
                    closeParagraph()
                    paragraph = (segment.speaker, segment.start, [segment.text])
                }
            case .note(let note):
                closeParagraph()
                blocks.append("> **Note** · \(MeetingTime.format(note.time)) · \(indented(note.text, by: "> "))")
            case .marker(let marker):
                closeParagraph()
                blocks.append(markerLine(marker))
            }
        }
        closeParagraph()
        return blocks
    }

    private static func markerLine(_ marker: Marker) -> String {
        let span = "\(MeetingTime.format(marker.start))–\(MeetingTime.format(marker.end))"
        return switch marker.kind {
        case .gap: "> **Gap** · \(span) · connection lost, audio kept"
        case .paused: "> **Paused** · \(span)"
        case .sleep: "> **Paused** · \(span) · Mac slept"
        }
    }

    /// Continuation lines of a multi-line note keep the note's block quote or list item.
    private static func indented(_ text: String, by prefix: String) -> String {
        text.components(separatedBy: "\n").joined(separator: "\n" + prefix)
    }

    // MARK: - Header

    private static func frontMatter(
        _ m: LoadedMeeting, timeZone: TimeZone, fields: [(key: String, value: String)]
    ) -> String {
        let meeting = m.meeting
        var lines = [
            "---",
            "title: \(yaml(meeting.title))",
            "id: \(meeting.id.uuidString.lowercased())",
            "date: \(format(meeting.startedAt, "yyyy-MM-dd", timeZone))",
            "start: \"\(format(meeting.startedAt, "HH:mm", timeZone))\"",
            "end: \"\(format(endDate(meeting), "HH:mm", timeZone))\"",
            "duration: \"\(MeetingTime.format(meeting.durationSeconds))\"",
            "mode: \(meeting.mode.rawValue)",
        ]
        if let app = meeting.app { lines.append("app: \(yaml(app))") }
        lines += fields.map { "\($0.key): \($0.value)" }
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func metaLine(_ m: LoadedMeeting, timeZone: TimeZone) -> String {
        let meeting = m.meeting
        let span = "\(format(meeting.startedAt, "HH:mm", timeZone))–\(format(endDate(meeting), "HH:mm", timeZone))"
        let mode = switch meeting.mode {
        case .remote: "Remote call"
        case .inRoom: "In the room"
        }
        let names = speakerNames(m)
        let parts = [format(meeting.startedAt, "d MMMM yyyy", timeZone), span, mode]
            + (names.isEmpty ? [] : [names.joined(separator: ", ")])
        return parts.joined(separator: " · ")
    }

    /// A meeting still recording has no end yet.
    private static func endDate(_ meeting: Meeting) -> Date {
        meeting.endedAt ?? meeting.startedAt.addingTimeInterval(meeting.durationSeconds)
    }

    /// Names of the speakers in the transcript, in order of first appearance.
    private static func speakerNames(_ m: LoadedMeeting) -> [String] {
        var names: [String] = []
        for segment in m.segments.sorted(by: { $0.start < $1.start }) {
            let name = name(of: segment.speaker, in: m)
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    private static func speakerList(_ m: LoadedMeeting) -> String {
        "[" + speakerNames(m).map { yaml($0, inFlow: true) }.joined(separator: ", ") + "]"
    }

    private static func name(of speaker: Int, in m: LoadedMeeting) -> String {
        m.meeting.speakers.first { $0.id == speaker }?.name ?? "Speaker \(speaker)"
    }

    /// "claude-sonnet-5-5" → "Claude Sonnet 5.5"; any other id is shown as is.
    private static func modelName(_ id: String) -> String {
        let parts = id.split(separator: "-").map(String.init)
        guard parts.count >= 3, parts.count <= 4, parts[0] == "claude",
              parts[2...].allSatisfy({ $0.count <= 2 && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return id }
        return "Claude \(parts[1].capitalized) \(parts[2...].joined(separator: "."))"
    }

    private static func plural(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    // MARK: - Formatting

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static func utcTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static let indicators = Set("-?:,[]{}#&*!|>'\"%@`+.")
    private static let reservedWords: Set<String> = ["y", "n", "yes", "no", "true", "false", "on", "off", "null", "~"]

    /// A YAML scalar: plain when a parser reads it back as the same string, double-quoted otherwise.
    private static func yaml(_ value: String, inFlow: Bool = false) -> String {
        guard needsQuotes(value, inFlow: inFlow) else { return value }
        var quoted = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": quoted += "\\\\"
            case "\"": quoted += "\\\""
            case _ where scalar.properties.generalCategory == .control:
                quoted += String(format: "\\u%04X", scalar.value)
            default: quoted.unicodeScalars.append(scalar)
            }
        }
        return quoted + "\""
    }

    private static func needsQuotes(_ value: String, inFlow: Bool) -> Bool {
        guard let first = value.first, let last = value.last else { return true }
        return first.isWhitespace || last.isWhitespace || last == ":"
            || indicators.contains(first) || first.isNumber
            || value.contains(": ") || value.contains(" #")
            || value.unicodeScalars.contains { $0.properties.generalCategory == .control }
            || reservedWords.contains(value.lowercased())
            || (inFlow && value.contains { ",[]{}".contains($0) })
    }
}
