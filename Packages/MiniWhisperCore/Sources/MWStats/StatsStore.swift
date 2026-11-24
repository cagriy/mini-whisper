import Foundation
import MWSupport
import MWUsage

/// The statistics record in `stats/`: every row held in memory, every change one appended line.
/// No entry point throws; a file that cannot be written is logged and memory moves on regardless.
public actor StatsStore: DictationStatsRecording {
    /// `days.jsonl` is refolded after this many appended lines, keeping it near one line a day.
    private static let foldEvery = 2_000

    /// One element after each recorded row, keeping only the newest while nobody reads.
    public nonisolated let changes: AsyncStream<Void>
    private let changed: AsyncStream<Void>.Continuation
    private let now: @Sendable () -> Date
    private let calendar: @Sendable () -> Calendar
    private let dictationsFile: JSONLFile
    private let daysFile: JSONLFile
    private let meetingsFile: JSONLFile
    private let metaURL: URL

    private var meta: StatsMeta?
    private var dictations: [DictationRow] = []
    private var days: [DayRow] = []
    private var dayIndex: [String: Int] = [:]
    private var meetings: [MeetingRow] = []
    private var meetingIndex: [UUID: Int] = [:]
    private var dayLines = 0
    private var dayLinesSinceFold = 0
    private var prunedOn: String?
    /// Files that failed to read at open: memory lacks their lines, so rewriting one from memory
    /// would lose them.
    private var unread: Set<URL> = []

    public init(
        directory: URL,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: @escaping @Sendable () -> Calendar = { .current }
    ) {
        self.now = now
        self.calendar = calendar
        dictationsFile = JSONLFile(url: directory.appendingPathComponent("dictations.jsonl"))
        daysFile = JSONLFile(url: directory.appendingPathComponent("days.jsonl"))
        meetingsFile = JSONLFile(url: directory.appendingPathComponent("meetings.jsonl"))
        metaURL = directory.appendingPathComponent("meta.json")
        (changes, changed) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// True until `meta.json` exists, so a seed cut short runs again.
    public var needsSeed: Bool {
        !FileManager.default.fileExists(atPath: metaURL.path)
    }

    /// Loads the three files and `meta.json`, prunes old dictation rows and rewrites any file
    /// holding lines it no longer needs: a torn line, a superseded meeting row, more than one line
    /// a day.
    public func open() {
        let date = now()
        let calendar = self.calendar()
        unread = []

        let dictationFile = load(dictationsFile, as: DictationRow.self)
        dictations = dictationFile.rows
        prune(date, calendar, fileLines: dictationFile.lines)

        days = []
        dayIndex = [:]
        let dayFile = load(daysFile, as: DayRow.self)
        for line in dayFile.rows { fold(line) }
        dayLines = dayFile.lines
        dayLinesSinceFold = 0
        if dayLines > days.count { compactDays() }
        meta = loadMeta(date, calendar)

        meetings = []
        meetingIndex = [:]
        let meetingFile = load(meetingsFile, as: MeetingRow.self)
        for row in meetingFile.rows { place(row) }
        if meetingFile.lines > meetings.count, rewrite(meetings, to: meetingsFile) {
            Log.stats.info("compacted meetings.jsonl, \(meetingFile.lines) lines to \(meetings.count)")
        }

        Log.stats.info("opened, \(dictations.count) dictations, \(days.count) days, \(meetings.count) meetings")
    }

    /// One row in `dictations.jsonl` and one line in `days.jsonl`, stamped now. The first attempt
    /// of a new local day prunes first.
    public func record(_ attempt: DictationAttempt) {
        let date = now()
        let calendar = self.calendar()
        let day = StatsTime.dayKey(date, calendar: calendar)
        if day != prunedOn { prune(date, calendar, fileLines: dictations.count) }

        let row = DictationRow(
            id: attempt.id, at: StatsTime.iso(date, timeZone: calendar.timeZone), app: attempt.bundleID,
            engine: attempt.engine, seconds: attempt.seconds, words: attempt.words, outcome: attempt.outcome,
            wait: attempt.wait, usd: attempt.costUSD
        )
        dictations.append(row)
        append(row, to: dictationsFile)

        var line = DayRow(day: day)
        if attempt.outcome == .delivered {
            line.delivered = 1
            line.words = attempt.words
            if attempt.seconds > 0 {
                line.seconds = attempt.seconds
                line.timedWords = attempt.words
            }
            line.apps[attempt.bundleID ?? "other"] = 1
            line.hours[String(StatsTime.hour(date, calendar: calendar))] = 1
        } else {
            line.undelivered[attempt.outcome.rawValue] = 1
        }
        addDayLine(line)
        changed.yield()
    }

    /// One line in `days.jsonl` under the usage's purpose. A test call's usage is not recorded.
    public func record(spend usage: ProviderUsage) {
        guard usage.purpose != .testCall else { return }
        let spend = Spend(
            usd: usage.costUSD, tokensIn: usage.inputTokens, tokensOut: usage.outputTokens,
            seconds: usage.streamedSeconds
        )
        let day = StatsTime.dayKey(now(), calendar: calendar())
        addDayLine(DayRow(day: day, spend: [usage.purpose.rawValue: spend]))
        changed.yield()
    }

    /// Appended; replaces the meeting's earlier row in memory at once and in the file at the next
    /// open.
    public func upsert(_ row: MeetingRow) {
        place(row)
        append(row, to: meetingsFile)
        changed.yield()
    }

    /// Replaces the whole record with `seed`. `meta.json` goes first and is written back only once
    /// every other file is in place, so seeding cut short anywhere runs again at the next launch.
    public func seed(_ seed: StatsSeed) {
        let date = now()
        let calendar = self.calendar()
        unread = []
        let removed = [metaURL, dictationsFile.url, daysFile.url, meetingsFile.url].map { remove($0) }

        dictations = seed.dictations
        days = []
        dayIndex = [:]
        for line in seed.days { fold(line) }
        meetings = []
        meetingIndex = [:]
        dayLines = days.count
        dayLinesSinceFold = 0
        prunedOn = nil
        let written = [
            dictations.isEmpty || rewrite(dictations, to: dictationsFile),
            days.isEmpty || rewrite(days, to: daysFile),
        ]

        let meta = StatsMeta(
            since: StatsTime.dayKey(date, calendar: calendar), created: StatsTime.iso(date, timeZone: .gmt)
        )
        self.meta = meta
        if !(removed + written).contains(false) { writeMeta(meta) }
        Log.stats.info(
            "seeded \(dictations.count) dictations, \(days.count) days, \(seed.meetingsWithCost) meetings with cost"
        )
        changed.yield()
    }

    /// Erases and seeds in one call, so no row can land in between.
    public func reset(_ seed: StatsSeed) {
        Log.stats.info("reset")
        self.seed(seed)
    }

    public func meetingRows() -> [UUID: MeetingRow] {
        Dictionary(uniqueKeysWithValues: meetings.map { ($0.id, $0) })
    }

    public func snapshot() -> StatsSnapshot {
        StatsSnapshot(dictations: dictations, days: days, meetings: meetings, meta: meta)
    }

    // MARK: - Memory

    /// Drops rows older than 13 months, then rewrites `dictations.jsonl` when it holds more lines
    /// than rows. A row whose time cannot be read stays.
    private func prune(_ date: Date, _ calendar: Calendar, fileLines: Int) {
        prunedOn = StatsTime.dayKey(date, calendar: calendar)
        let cutoff = StatsTime.dictationCutoff(now: date, calendar: calendar)
        let count = dictations.count
        dictations.removeAll { row in StatsTime.parse(row.at).map { $0.date < cutoff } ?? false }
        let pruned = count - dictations.count
        guard fileLines > dictations.count, rewrite(dictations, to: dictationsFile), pruned > 0 else { return }
        Log.stats.info("pruned \(pruned) dictation rows")
    }

    private func fold(_ line: DayRow) {
        if let index = dayIndex[line.day] {
            days[index].add(line)
        } else if let last = days.last, last.day > line.day {
            // Only after the clock or time zone moves back does a new day sort before the last.
            days.insert(line, at: days.firstIndex { $0.day > line.day } ?? days.endIndex)
            dayIndex = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1.day, $0) })
        } else {
            dayIndex[line.day] = days.count
            days.append(line)
        }
    }

    private func place(_ row: MeetingRow) {
        if let index = meetingIndex[row.id] {
            meetings[index] = row
        } else {
            meetingIndex[row.id] = meetings.count
            meetings.append(row)
        }
    }

    // MARK: - Files

    private func addDayLine(_ line: DayRow) {
        fold(line)
        guard append(line, to: daysFile) else { return }
        dayLines += 1
        dayLinesSinceFold += 1
        if dayLinesSinceFold >= Self.foldEvery { compactDays() }
    }

    private func compactDays() {
        dayLinesSinceFold = 0
        guard rewrite(days, to: daysFile) else { return }
        Log.stats.info("compacted days.jsonl, \(dayLines) lines to \(days.count)")
        dayLines = days.count
    }

    /// `lines` counts the unreadable ones too, so a torn line makes a file worth rewriting.
    private func load<Row: Decodable>(_ file: JSONLFile, as type: Row.Type) -> (rows: [Row], lines: Int) {
        do {
            let read = try file.read(type)
            return (read.values, read.values.count + read.skipped)
        } catch {
            unread.insert(file.url)
            Log.stats.warning("\(file.url.lastPathComponent) not read: \(AnyError(error).description)")
            return ([], 0)
        }
    }

    /// Nil when absent. One that exists but cannot be read is written anew from the earliest day
    /// held, since the record it marks is still there.
    private func loadMeta(_ date: Date, _ calendar: Calendar) -> StatsMeta? {
        do {
            return try JSONDecoder().decode(StatsMeta.self, from: Data(contentsOf: metaURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            Log.stats.warning("meta.json not read: \(AnyError(error).description)")
            let meta = StatsMeta(
                since: days.first?.day ?? StatsTime.dayKey(date, calendar: calendar),
                created: StatsTime.iso(date, timeZone: .gmt)
            )
            writeMeta(meta)
            return meta
        }
    }

    private func writeMeta(_ meta: StatsMeta) {
        write(metaURL) { try JSONLFile.writeAtomically(meta, to: metaURL) }
    }

    /// True once the file is gone, including when it never existed.
    private func remove(_ url: URL) -> Bool {
        write(url) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {}
        }
    }

    @discardableResult
    private func append(_ value: some Encodable, to file: JSONLFile) -> Bool {
        write(file.url) { try file.append(value) }
    }

    private func rewrite<Row: Encodable>(_ rows: [Row], to file: JSONLFile) -> Bool {
        !unread.contains(file.url) && write(file.url) { try file.rewrite(rows) }
    }

    @discardableResult
    private func write(_ url: URL, _ body: () throws -> Void) -> Bool {
        do {
            try body()
            return true
        } catch {
            Log.stats.warning("\(url.lastPathComponent) not written: \(AnyError(error).description)")
            return false
        }
    }
}
