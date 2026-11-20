import Foundation
import MWConfig
import MWMeetings

/// `voice-matches.jsonl` (R23): one JSON line per match and per user action on one, the record a
/// later calibration reads. Lines name people by id only. The file is 0600; an append that takes
/// it past `limit` bytes drops the oldest half of the lines.
public actor MatchLog {
    public enum Event: String, Codable, Sendable, CaseIterable {
        case suggested, applied, accepted, dismissed, rejected, renamed
    }

    public struct Entry: Codable, Sendable, Equatable {
        public var at: Date
        public var meeting: UUID
        /// The provider key, `"<session>:<label>"`.
        public var key: String
        public var route: VoiceRoute
        public var event: Event
        public var person: UUID?
        /// Nil on the Speechmatics route.
        public var score: Double?
        public var runnerUp: Double?
        /// The speech behind the key's voice.
        public var seconds: Double?

        public init(
            at: Date, meeting: UUID, key: String, route: VoiceRoute, event: Event, person: UUID?,
            score: Double? = nil, runnerUp: Double? = nil, seconds: Double? = nil
        ) {
            self.at = at
            self.meeting = meeting
            self.key = key
            self.route = route
            self.event = event
            self.person = person
            self.score = score
            self.runnerUp = runnerUp
            self.seconds = seconds
        }
    }

    private struct PersonField: Decodable {
        let person: UUID?
    }

    private let url: URL
    private let limit: Int

    public init(url: URL, limit: Int = 2 * 1024 * 1024) {
        self.url = url
        self.limit = limit
    }

    public func append(_ entry: Entry) throws {
        var line = try MeetingCoding.encoder().encode(entry)
        line.append(0x0A)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let handle = try PrivateFile.open(url, flags: O_APPEND)
        defer { try? handle.close() }
        try handle.write(contentsOf: line)
        guard Int(try handle.seekToEnd()) > limit else { return }
        let lines = try Self.lines(of: url)
        try Self.write(lines.dropFirst(lines.count / 2), to: url)
    }

    /// Drops every line naming one of `people`, and any line that cannot be read, since it may name one.
    public func remove(people: Set<UUID>) throws {
        let lines = try Self.lines(of: url)
        let decoder = MeetingCoding.decoder()
        let kept = lines.filter { line in
            guard let field = try? decoder.decode(PersonField.self, from: line) else { return false }
            return field.person.map { !people.contains($0) } ?? true
        }
        guard kept.count < lines.count else { return }
        try Self.write(kept, to: url)
    }

    public func removeAll() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Empty when the file is absent.
    private static func lines(of url: URL) throws -> [Data] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try Data(contentsOf: url).split(separator: 0x0A)
    }

    private static func write(_ lines: some Sequence<Data>, to url: URL) throws {
        var data = Data()
        for line in lines {
            data.append(line)
            data.append(0x0A)
        }
        try PrivateFile.replace(url, with: data)
    }
}
