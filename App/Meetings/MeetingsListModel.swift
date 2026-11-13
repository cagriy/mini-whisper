import Foundation
import MWMeetings
import MWSupport
import MWUsage
import Observation

/// What the Meetings page needs of the store; `MeetingStore` conforms. The list renames and
/// deletes through it directly (*Planning decisions taken* #22).
protocol MeetingLibrary: MeetingReading {
    var isIndexMissing: Bool { get }
    func refreshIndex() async throws -> [IndexEntry]
    func delete(_ id: UUID) async throws
    func deleteAudio(_ id: UUID) async throws
    func retitle(_ id: UUID, to title: String) async throws
}

extension MeetingStore: MeetingLibrary {
    func retitle(_ id: UUID, to title: String) throws {
        var meeting = try load(id).meeting
        meeting.title = title
        try update(meeting)
    }
}

/// Everything the Meetings page decides (design v6 §3 R18, §5.9; mockup
/// `mockup-v6-overview.html`): day groups, row and count texts, and the open, export, delete
/// and rename intents.
@MainActor
@Observable
final class MeetingsListModel {
    struct Dependencies {
        var library: any MeetingLibrary
        var now: @Sendable () -> Date
        /// Its time zone sets the day groups and start times.
        var calendar: Calendar
        /// The meeting hotkey as shown, for the empty state.
        var hotkey: @MainActor () -> String
        /// A meeting held by a session: its own controller renames it, and it cannot be deleted.
        var isOpen: @MainActor (UUID) -> Bool
        /// Renames an open meeting through its window; false when it is not open.
        var retitleOpen: @MainActor (UUID, String) async -> Bool
        var open: @MainActor (UUID) async throws -> Void
        var export: @MainActor (MeetingExporter.Kind, UUID) -> Void
        var startMeeting: @MainActor () -> Void
        var showInFinder: @MainActor () -> Void
    }

    struct Row: Identifiable, Equatable {
        let id: UUID
        let title: String
        let mode: MeetingMode
        /// R18: the summary's topics or first sentence; without a summary, the first transcript
        /// line in curly quotes.
        let subLine: String
        /// The sub line quotes the transcript, and is shown in italics.
        let subLineIsTranscript: Bool
        let meta: String
        /// The start, "14:30".
        let time: String
        let audioBytes: Int
        /// A test call: the TEST chip follows the title (R23).
        let isTest: Bool
    }

    struct DayGroup: Identifiable, Equatable {
        let id: Date
        let title: String
        let rows: [Row]
    }

    /// One entry of a row's Export ▾ menu.
    struct ExportItem: Equatable {
        enum Action: Equatable {
            case export(MeetingExporter.Kind)
            case deleteAudio
        }

        let title: String
        let action: Action
    }

    /// A delete waiting for its confirmation.
    struct Deletion: Equatable {
        let id: UUID
        let audioOnly: Bool
        let prompt: String
        let detail: String
        let confirmTitle: String
    }

    private let deps: Dependencies
    @ObservationIgnored private let timeFormat: DateFormatter
    @ObservationIgnored private let dayFormat: DateFormatter
    /// Newest first.
    private(set) var entries: [IndexEntry] = []
    private(set) var pendingDeletion: Deletion?
    private(set) var errorMessage: String?

    init(deps: Dependencies) {
        self.deps = deps
        timeFormat = Self.formatter("HH:mm", deps.calendar)
        dayFormat = Self.formatter("EEEE d MMM", deps.calendar)
    }

    // MARK: - Outputs

    var days: [DayGroup] {
        var groups: [(day: Date, rows: [Row])] = []
        for entry in entries {
            let day = deps.calendar.startOfDay(for: entry.startedAt)
            if groups.last?.day == day {
                groups[groups.count - 1].rows.append(row(for: entry))
            } else {
                groups.append((day, [row(for: entry)]))
            }
        }
        return groups.map { DayGroup(id: $0.day, title: dayTitle($0.day), rows: $0.rows) }
    }

    /// "12 meetings · 310 MB audio", under the page title.
    var footer: String {
        let audio = entries.reduce(0) { $0 + $1.audioBytes }
        let count = Self.plural(entries.count, "meeting")
        return audio > 0 ? "\(count) · \(Self.size(audio)) audio" : count
    }

    /// R16: before the first meeting, the message naming the hotkey.
    var emptyState: String? {
        guard entries.isEmpty else { return nil }
        return "Press \(deps.hotkey()) or choose Start Meeting… from the menu bar. Mini Whisper transcribes live with"
            + " speaker labels, keeps your notes beside the transcript and writes a summary when you stop."
    }

    func canDelete(_ row: Row) -> Bool {
        !deps.isOpen(row.id)
    }

    /// Why Delete is disabled (R12), or nil when it is not.
    func deleteHelp(_ row: Row) -> String? {
        canDelete(row) ? nil : "This meeting is recording, on screen, or its summary is being written"
    }

    func exportItems(for row: Row) -> [ExportItem] {
        var items = [
            ExportItem(title: "Export transcript…", action: .export(.transcript)),
            ExportItem(title: "Export summary…", action: .export(.summary)),
            ExportItem(title: "Export both…", action: .export(.both)),
        ]
        if row.audioBytes > 0 {
            items.append(ExportItem(title: "Delete audio (\(Self.size(row.audioBytes)))", action: .deleteAudio))
        }
        return items
    }

    // MARK: - Intents

    /// §5.7 Missing `index.json`: rebuilt by folder scan on the first list.
    func reload() async {
        do {
            let library = deps.library
            let listed = library.isIndexMissing ? try await library.refreshIndex() : try library.index()
            entries = listed.sorted { $0.startedAt > $1.startedAt }
            errorMessage = nil
        } catch {
            show(error, doing: "list")
        }
    }

    func open(_ row: Row) async {
        do {
            try await deps.open(row.id)
        } catch {
            show(error, doing: "open")
        }
    }

    func perform(_ item: ExportItem, on row: Row) {
        switch item.action {
        case .export(let kind): deps.export(kind, row.id)
        case .deleteAudio: requestDelete(row, audioOnly: true)
        }
    }

    func requestDelete(_ row: Row, audioOnly: Bool = false) {
        guard canDelete(row) else { return }
        pendingDeletion = audioOnly
            ? Deletion(
                id: row.id, audioOnly: true, prompt: "Delete the audio of “\(row.title)”?",
                detail: "The transcript, notes and summary stay.", confirmTitle: "Delete Audio"
            )
            : Deletion(
                id: row.id, audioOnly: false, prompt: "Delete “\(row.title)”?",
                detail: "Its transcript, notes, summary and audio are removed. This cannot be undone.",
                confirmTitle: "Delete"
            )
    }

    func cancelDeletion() {
        pendingDeletion = nil
    }

    func confirmDeletion() async {
        guard let deletion = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            if deletion.audioOnly {
                try await deps.library.deleteAudio(deletion.id)
            } else {
                try await deps.library.delete(deletion.id)
            }
        } catch {
            show(error, doing: "delete")
        }
        await reload()
    }

    /// R15: an open meeting renames through its window, so its next save keeps the title.
    func rename(_ row: Row, to title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != row.title else { return }
        if await !deps.retitleOpen(row.id, title) {
            do {
                try await deps.library.retitle(row.id, to: title)
            } catch {
                show(error, doing: "rename")
            }
        }
        await reload()
    }

    func startMeeting() { deps.startMeeting() }

    func showInFinder() { deps.showInFinder() }

    // MARK: - Presentation

    private func row(for entry: IndexEntry) -> Row {
        let quoted = !entry.hasSummary && !entry.excerpt.isEmpty
        return Row(
            id: entry.id,
            title: entry.title,
            mode: entry.mode,
            subLine: quoted ? "\u{201C}\(entry.excerpt)\u{201D}" : entry.excerpt,
            subLineIsTranscript: !entry.hasSummary,
            meta: meta(of: entry),
            time: timeFormat.string(from: entry.startedAt),
            audioBytes: entry.audioBytes,
            isTest: entry.test != nil
        )
    }

    /// "48 min · Remote call · 3 speakers · $0.40"; a test call reads
    /// "2 min · WER 6.4% · AssemblyAI Universal-Streaming · $0.02", without the WER until it is scored.
    private func meta(of entry: IndexEntry) -> String {
        var parts = [Self.duration(entry.duration)]
        if let test = entry.test {
            if let wer = test.wer { parts.append(String(format: "WER %.1f%%", wer * 100)) }
            parts += [entry.engine.title, Pricing.dollars(entry.costUSD)]
            return parts.joined(separator: " · ")
        }
        parts += [
            MeetingWindowModel.title(of: entry.mode),
            Self.plural(entry.speakerCount, "speaker"),
            Pricing.dollars(entry.costUSD),
        ]
        if !entry.hasSummary { parts.append("No summary") }
        return parts.joined(separator: " · ")
    }

    private func dayTitle(_ day: Date) -> String {
        Self.dayTitle(day, now: deps.now(), calendar: deps.calendar, format: dayFormat)
    }

    /// "Today", "Yesterday", or the day as `format` writes it.
    static func dayTitle(_ day: Date, now: Date, calendar: Calendar, format: DateFormatter) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return format.string(from: day)
    }

    static func formatter(_ pattern: String, _ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter
    }

    /// "48 min", "1 h 12 min", "2 h 04 min".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(max(0, seconds)) / 60
        guard minutes >= 60 else { return "\(minutes) min" }
        return String(format: "%d h %02d min", minutes / 60, minutes % 60)
    }

    /// Decimal megabytes, as Finder shows them.
    private static func size(_ bytes: Int) -> String {
        bytes >= 1_000_000_000
            ? String(format: "%.1f GB", Double(bytes) / 1e9)
            : "\(max(1, Int((Double(bytes) / 1e6).rounded()))) MB"
    }

    private static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private func show(_ error: any Error, doing action: String) {
        let reason = AnyError(error).description
        Log.meeting.warning("meetings list: \(action) failed: \(reason)")
        errorMessage = reason
    }
}
