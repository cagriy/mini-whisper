import Foundation
import MWSupport

/// Read-only access to stored meetings. The CLI and MCP server are handed only this, so
/// no write is reachable from them (design §5.8).
public protocol MeetingReading: Sendable {
    func index() throws -> [IndexEntry]
    func load(_ id: UUID) throws -> LoadedMeeting
}

/// `meetings/`: `index.json` plus one 0700 folder per meeting holding 0600 files
/// (design §5.2). Whole-file writes go to a temp file renamed into place, so a reader in
/// another process sees either the old or the new file. Reads are nonisolated and never
/// write: a missing index is rebuilt in memory, and only `refreshIndex()` persists it.
public actor MeetingStore: MeetingReading {
    private enum File: String {
        case meeting = "meeting.json"
        case segments = "segments.jsonl"
        case notes = "notes.jsonl"
        case audio = "audio.m4a"
        case testCall = "testcall.json"
    }

    public nonisolated let directory: URL
    /// Append handles, kept open while a meeting records. A rewrite or delete closes them.
    private var handles: [URL: FileHandle] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Writes

    public func create(_ meeting: Meeting) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createDirectory(
            at: folder(meeting.id), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
        )
        try Self.write(MeetingCoding.encoder().encode(meeting), to: url(.meeting, of: meeting.id))
        try Self.write(Data(), to: url(.segments, of: meeting.id))
        try Self.write(Data(), to: url(.notes, of: meeting.id))
        try updateIndexEntry(for: meeting)
    }

    public func append(_ segment: Segment, to id: UUID) throws {
        try appendLine(segment, to: url(.segments, of: id))
    }

    public func append(_ note: Note, to id: UUID) throws {
        try appendLine(note, to: url(.notes, of: id))
    }

    /// Rewrites `meeting.json` and its index entry.
    public func update(_ meeting: Meeting) throws {
        try Self.write(MeetingCoding.encoder().encode(meeting), to: url(.meeting, of: meeting.id))
        try updateIndexEntry(for: meeting)
    }

    public func rewriteSegments(_ segments: [Segment], of id: UUID) throws {
        let encoder = MeetingCoding.encoder()
        var data = Data()
        for segment in segments {
            data.append(try encoder.encode(segment))
            data.append(0x0A)
        }
        let target = url(.segments, of: id)
        // The rename below would leave an open handle appending to the replaced file.
        try? handles.removeValue(forKey: target)?.close()
        try Self.write(data, to: target)
        try updateIndexEntry(for: readMeeting(id))
    }

    public func delete(_ id: UUID) throws {
        for file in [File.segments, .notes] {
            try? handles.removeValue(forKey: url(file, of: id))?.close()
        }
        if FileManager.default.fileExists(atPath: folder(id).path) {
            try FileManager.default.removeItem(at: folder(id))
        }
        try writeIndex(readIndexOrScan().filter { $0.id != id })
    }

    public func deleteAudio(_ id: UUID) throws {
        let audio = audioURL(id)
        if FileManager.default.fileExists(atPath: audio.path) {
            try FileManager.default.removeItem(at: audio)
        }
        try updateIndexEntry(for: readMeeting(id))
    }

    public func writeTestCall(_ record: TestCallRecord, of id: UUID) throws {
        try Self.write(MeetingCoding.encoder().encode(record), to: url(.testCall, of: id))
    }

    /// Rebuilds `index.json` from the meeting folders and writes it.
    @discardableResult
    public func refreshIndex() throws -> [IndexEntry] {
        let entries = try scan()
        try writeIndex(entries)
        return entries
    }

    // MARK: - Reads

    public nonisolated func audioURL(_ id: UUID) -> URL {
        url(.audio, of: id)
    }

    /// The folder exists without `index.json`, so `refreshIndex()` should write one (§5.7).
    public nonisolated var isIndexMissing: Bool {
        FileManager.default.fileExists(atPath: directory.path)
            && !FileManager.default.fileExists(atPath: indexURL.path)
    }

    /// Newest first.
    public nonisolated func index() throws -> [IndexEntry] {
        try readIndexOrScan()
    }

    /// Skips, and counts in the log, any unreadable segment or note line.
    public nonisolated func load(_ id: UUID) throws -> LoadedMeeting {
        LoadedMeeting(
            meeting: try readMeeting(id),
            segments: readLines(of: .segments, in: id),
            notes: readLines(of: .notes, in: id)
        )
    }

    /// Nil when the meeting has no `testcall.json`.
    public nonisolated func readTestCall(_ id: UUID) throws -> TestCallRecord? {
        guard let data = FileManager.default.contents(atPath: url(.testCall, of: id).path) else { return nil }
        return try MeetingCoding.decoder().decode(TestCallRecord.self, from: data)
    }

    // MARK: - Paths

    private nonisolated var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }

    private nonisolated func folder(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private nonisolated func url(_ file: File, of id: UUID) -> URL {
        folder(id).appendingPathComponent(file.rawValue)
    }

    // MARK: - Internals

    private func appendLine(_ value: some Encodable, to url: URL) throws {
        var line = try MeetingCoding.encoder().encode(value)
        line.append(0x0A)
        try handle(for: url).write(contentsOf: line)
    }

    private func handle(for url: URL) throws -> FileHandle {
        if let handle = handles[url] { return handle }
        if !FileManager.default.fileExists(atPath: url.path) { try Self.write(Data(), to: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        handles[url] = handle
        return handle
    }

    private func updateIndexEntry(for meeting: Meeting) throws {
        try writeIndex(readIndexOrScan().filter { $0.id != meeting.id } + [entry(for: meeting)])
    }

    private func writeIndex(_ entries: [IndexEntry]) throws {
        try Self.write(MeetingCoding.encoder().encode(Self.newestFirst(entries)), to: indexURL)
    }

    private nonisolated func readMeeting(_ id: UUID) throws -> Meeting {
        try MeetingCoding.decoder().decode(Meeting.self, from: Data(contentsOf: url(.meeting, of: id)))
    }

    private nonisolated func readLines<Line: Decodable>(of file: File, in id: UUID) -> [Line] {
        guard let data = FileManager.default.contents(atPath: url(file, of: id).path) else { return [] }
        let decoder = MeetingCoding.decoder()
        var lines: [Line] = []
        var skipped = 0
        for line in data.split(separator: 0x0A) {
            if let value = try? decoder.decode(Line.self, from: Data(line)) {
                lines.append(value)
            } else {
                skipped += 1
            }
        }
        // The count only: transcript text is never logged.
        if skipped > 0 { Log.meeting.warning("\(file.rawValue): skipped \(skipped) unreadable line(s)") }
        return lines
    }

    private nonisolated func readIndexOrScan() throws -> [IndexEntry] {
        guard let data = FileManager.default.contents(atPath: indexURL.path) else { return try scan() }
        do {
            return try MeetingCoding.decoder().decode([IndexEntry].self, from: data)
        } catch {
            Log.meeting.warning("index.json unreadable, rebuilding: \(AnyError(error).description)")
            return try scan()
        }
    }

    private nonisolated func scan() throws -> [IndexEntry] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var entries: [IndexEntry] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            guard let id = UUID(uuidString: name) else { continue }
            do {
                entries.append(entry(for: try readMeeting(id)))
            } catch {
                Log.meeting.warning("skipped meeting \(id.uuidString): \(AnyError(error).description)")
            }
        }
        return Self.newestFirst(entries)
    }

    private nonisolated func entry(for meeting: Meeting) -> IndexEntry {
        let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL(meeting.id).path)
        return IndexEntry(
            id: meeting.id,
            title: meeting.title,
            startedAt: meeting.startedAt,
            endedAt: meeting.endedAt,
            duration: meeting.durationSeconds,
            mode: meeting.mode,
            app: meeting.app,
            engine: meeting.engine,
            speakerCount: meeting.speakers.count,
            costUSD: meeting.totalCostUSD,
            hasSummary: meeting.summary != nil,
            audioBytes: (attributes?[.size] as? Int) ?? 0,
            excerpt: meeting.summary.map { SummaryDocument.excerpt(ofSummary: $0.text) }
                ?? firstSegment(of: meeting.id)?.text ?? "",
            test: meeting.test
        )
    }

    /// Reads up to the first newline only: a long meeting's transcript stays on disk.
    private nonisolated func firstSegment(of id: UUID) -> Segment? {
        guard let handle = FileHandle(forReadingAtPath: url(.segments, of: id).path) else { return nil }
        defer { try? handle.close() }
        var line = Data()
        while let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty {
            if let newline = chunk.firstIndex(of: 0x0A) {
                line.append(chunk[..<newline])
                break
            }
            line.append(chunk)
        }
        return try? MeetingCoding.decoder().decode(Segment.self, from: line)
    }

    private static func newestFirst(_ entries: [IndexEntry]) -> [IndexEntry] {
        entries.sorted { $0.startedAt > $1.startedAt }
    }

    /// Temp file in the same folder, 0600, renamed over the target.
    private static func write(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try data.write(to: temp, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
            guard rename(temp.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}
