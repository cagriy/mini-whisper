import Foundation
import MWConfig
import MWHistory
import MWPaste
import MWPipeline
import MWSupport
import MWUsage
import Observation

/// Everything the History window decides (design §5.4, F29/F30): day grouping,
/// search, the row and footer strings, and the three row actions. `HistoryView`
/// is a projection of this — it holds no rules of its own.
@MainActor
@Observable
final class HistoryListModel {
    struct Dependencies {
        var history: HistoryStore
        var paster: any Pasting
        var pasteboard: any PasteboardAccess
        var isRunning: @Sendable (pid_t) -> Bool
        var retentionDays: @Sendable () -> Int
        var clock: any MWSupport.Clock
        var now: @Sendable () -> Date
        /// F30: the window is out of the way before the previous app comes forward.
        var hide: @MainActor () -> Void
        var activate: @MainActor (PasteTarget) -> Void
    }

    struct Row: Identifiable, Equatable {
        let id: String
        let text: String
        let meta: String
        let glyph: AppGlyph
    }

    struct DayGroup: Identifiable, Equatable {
        let id: String
        let title: String
        let rows: [Row]
    }

    /// F30's settle time between activating the target and posting ⌘V.
    private static let pasteDelay = Duration.milliseconds(150)

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    private let deps: Dependencies

    /// Case-insensitive substring search, applied by `reload()` (F29).
    var query = ""
    /// The app that was frontmost when the window was shown — the paste target (F30).
    var previousApp: PasteTarget?
    private(set) var days: [DayGroup] = []

    init(deps: Dependencies) {
        self.deps = deps
    }

    private var count: Int { days.reduce(0) { $0 + $1.rows.count } }

    var footer: String {
        let dictations = "\(count) dictation\(count == 1 ? "" : "s")"
        let days = deps.retentionDays()
        guard days > 0 else { return "History off · \(dictations)" }
        return "Keeping \(days) day\(days == 1 ? "" : "s") · \(dictations)"
    }

    var pasteTitle: String? {
        previousApp.map { "Paste into \($0.name)" }
    }

    var canPaste: Bool {
        guard let previousApp else { return false }
        return deps.isRunning(previousApp.pid)
    }

    func reload() async {
        days = Self.group(await deps.history.search(query), now: deps.now())
    }

    func copy(_ row: Row) {
        _ = deps.pasteboard.write(row.text)
    }

    func delete(_ row: Row) async {
        do {
            try await deps.history.delete(id: row.id)
        } catch {
            Log.ui.error("history: delete failed: \(AnyError(error).description)")
        }
        await reload()
    }

    func clear() async {
        do {
            try await deps.history.clear()
        } catch {
            Log.ui.error("history: clear failed: \(AnyError(error).description)")
        }
        await reload()
    }

    /// F30: hide, bring the previous app forward, let it settle, then paste to its
    /// pid with the submit key suppressed.
    func paste(_ row: Row) async {
        guard let target = previousApp, deps.isRunning(target.pid) else { return }
        deps.hide()
        deps.activate(target)
        try? await deps.clock.sleep(for: Self.pasteDelay)
        do {
            try await deps.paster.paste(row.text, into: target.pid, submit: nil)
        } catch {
            Log.ui.error("history: paste failed: \(AnyError(error).description)")
        }
    }

    // MARK: - Presentation

    private static func group(_ entries: [HistoryEntry], now: Date) -> [DayGroup] {
        let calendar = Calendar.current
        var groups: [DayGroup] = []
        var start: Date?
        var rows: [Row] = []

        func flush() {
            guard let start, !rows.isEmpty else { return }
            groups.append(DayGroup(
                id: String(start.timeIntervalSinceReferenceDate),
                title: title(for: start, now: now, calendar: calendar),
                rows: rows
            ))
        }

        for entry in entries.sorted(by: { $0.timestamp > $1.timestamp }) {
            let day = calendar.startOfDay(for: entry.timestamp)
            if day != start {
                flush()
                start = day
                rows = []
            }
            rows.append(Row(
                id: entry.id,
                text: entry.text,
                meta: meta(for: entry),
                glyph: AppGlyph(appName: entry.appName, bundleID: entry.bundleID)
            ))
        }
        flush()
        return groups
    }

    private static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return dayFormat.string(from: day)
    }

    /// `HH:mm · App · Engine · 6.2s · $0.001` (design §5.4); the seconds are dropped
    /// when nothing was streamed.
    private static func meta(for entry: HistoryEntry) -> String {
        var parts = [timeFormat.string(from: entry.timestamp), entry.appName]
        if let engine = entry.engine, !engine.isEmpty {
            parts.append(engineLabel(engine))
        }
        if entry.streamedSeconds > 0 {
            parts.append(String(format: "%.1fs", entry.streamedSeconds))
        }
        parts.append(Pricing.dollars(entry.costUSD, decimals: 3))
        return parts.joined(separator: " · ")
    }

    private static func engineLabel(_ stored: String) -> String {
        switch EngineName(rawValue: stored) {
        case .speechAnalyzer: "SpeechAnalyzer"
        case .onDevice: "On-device"
        case .openai: "OpenAI Realtime"
        case .elevenlabs: "ElevenLabs"
        case .speechmatics: "Speechmatics"
        case nil: stored
        }
    }
}
