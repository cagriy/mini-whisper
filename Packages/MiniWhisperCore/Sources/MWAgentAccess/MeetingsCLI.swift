import Foundation
import MWMeetings
import MWSupport

/// `mini-whisper meetings …` (design §5.3, R21). It is handed only a `MeetingReading`, so
/// no write is reachable. Exit 0 on success; 2 on a usage error, a bad or unknown id, or a
/// summary request for a meeting without one (planning decision 29).
public struct MeetingsCLI: Sendable {
    private static let usage = """
        usage: mini-whisper meetings list [--json]
               mini-whisper meetings transcript <id>
               mini-whisper meetings summary <id>
               mini-whisper meetings search <text> [--json]
        <id> is a meeting UUID or at least its first 8 hex characters.

        """
    private static let commands: Set = ["list", "transcript", "summary", "search"]

    /// One stderr line.
    private struct Failure: Error {
        let line: String
    }

    private let reader: any MeetingReading
    private let generator: String
    private let timeZone: TimeZone

    public init(reader: any MeetingReading, generator: String, timeZone: TimeZone = .current) {
        self.reader = reader
        self.generator = generator
        self.timeZone = timeZone
    }

    /// `arguments` follow `meetings`. `out` and `err` receive text to write verbatim; every
    /// piece ends in a newline.
    public func run(_ arguments: [String], out: (String) -> Void, err: (String) -> Void) -> Int32 {
        guard let command = arguments.first, Self.commands.contains(command) else { return usageError(err) }
        // The command name only: ids and search text stay out of the log.
        Log.meeting.info("cli: \(command)")
        let rest = Array(arguments.dropFirst())
        let json = rest.last == "--json"
        let operands = Array(rest.dropLast(json ? 1 : 0))

        let result: Result<String, Failure>
        switch (command, operands.count) {
        case ("list", 0):
            result = list(json: json)
        case ("transcript", 1) where !json:
            result = meeting(operands[0]).map {
                MeetingMarkdown.transcript($0, generator: generator, timeZone: timeZone)
            }
        case ("summary", 1) where !json:
            result = meeting(operands[0]).flatMap { loaded in
                Result { try MeetingMarkdown.summary(loaded, generator: generator, timeZone: timeZone) }
                    .mapError { _ in Failure(line: "no summary for meeting \(operands[0])") }
            }
        case ("search", _):
            let query = operands.joined(separator: " ")
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return usageError(err) }
            result = search(query, json: json)
        default:
            return usageError(err)
        }

        switch result {
        case .success(let text):
            out(text)
            return 0
        case .failure(let failure):
            err(failure.line + "\n")
            return 2
        }
    }

    private func usageError(_ err: (String) -> Void) -> Int32 {
        err(Self.usage)
        return 2
    }

    private func list(json: Bool) -> Result<String, Failure> {
        index().flatMap { entries in
            guard !json else { return encoded(entries) }
            let day = formatter("yyyy-MM-dd")
            let time = formatter("HH:mm")
            let lines = entries.map { entry in
                [
                    Self.idText(entry.id), day.string(from: entry.startedAt), time.string(from: entry.startedAt),
                    MeetingTime.format(entry.duration), entry.title,
                ].joined(separator: "  ") + "\n"
            }
            return .success(lines.joined())
        }
    }

    private func search(_ query: String, json: Bool) -> Result<String, Failure> {
        index().flatMap { entries in
            // An unreadable meeting is skipped, as the store skips it when rebuilding the index.
            let hits = MeetingSearch().search(query, in: entries.compactMap { try? reader.load($0.id) })
            guard !json else { return encoded(hits) }
            let titles = Dictionary(entries.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
            let lines = hits.flatMap { hit in
                let id = Self.idText(hit.meetingID)
                guard !hit.snippets.isEmpty else { return ["\(id)  -  title  \(titles[hit.meetingID] ?? "")\n"] }
                return hit.snippets.map { snippet in
                    let time = snippet.time.map(MeetingTime.format) ?? "-"
                    return "\(id)  \(time)  \(snippet.source.rawValue)  \(snippet.text)\n"
                }
            }
            return .success(lines.joined())
        }
    }

    private func meeting(_ text: String) -> Result<LoadedMeeting, Failure> {
        MeetingID.resolve(text, in: reader)
            .mapError { Failure(line: $0.localizedDescription) }
            .flatMap { id in
                Result { try reader.load(id) }
                    .mapError { Failure(line: "could not read meeting \(text): \($0.localizedDescription)") }
            }
    }

    private func index() -> Result<[IndexEntry], Failure> {
        Result { try reader.index() }
            .mapError { Failure(line: MeetingIDError.unreadable($0.localizedDescription).localizedDescription) }
    }

    private func encoded(_ value: some Encodable) -> Result<String, Failure> {
        Result { String(decoding: try MeetingCoding.encoder().encode(value), as: UTF8.self) + "\n" }
            .mapError { Failure(line: "could not encode JSON: \($0.localizedDescription)") }
    }

    private func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter
    }

    private static func idText(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}
