import Foundation
import MWMeetingPipeline
import MWMeetings
import MWTestCall
import Observation

/// The test call's right-hand pane (design §5.4): the script during the call, following the
/// conductor's events (mockup `mockup-v5-script-pane.html`), then the score once the controller
/// has one (mockup `mockup-v5-pane-score.html`).
@MainActor
@Observable
final class TestCallPaneModel {
    struct ScriptLine: Equatable, Identifiable {
        /// 1-based, as the conductor and the record number lines.
        let number: Int
        let role: TestCallRole
        /// "You", or the voice's character.
        let speaker: String
        let text: String
        var skipped = false

        var id: Int { number }
    }

    /// The tag above the current line.
    struct TurnTag: Equatable {
        let name: String
        let detail: String
        /// A voice is speaking, so the tag carries the level bars.
        let isVoice: Bool

        var text: String { "\(name) \(detail)" }
    }

    /// One role's figures in the score's head block.
    struct RoleRow: Equatable {
        let role: TestCallRole
        let name: String
        /// "read aloud", or the voice that played the role.
        let detail: String
        let wer: String
        /// The majority label's name at scoring.
        let label: String?
        let purity: String?
        /// Purity shows in amber when the role is not clean.
        let clean: Bool
    }

    struct Badge: Equatable {
        enum Kind {
            case ok
            case errors
            /// Skipped, stopped or not reached.
            case neutral
            /// Some of the line's words carry another role's label.
            case label
        }

        let kind: Kind
        let text: String
        var help: String?
    }

    struct ScoreRow: Equatable, Identifiable {
        let number: Int
        let role: TestCallRole
        let speaker: String
        let text: String
        let badges: [Badge]

        var id: Int { number }
    }

    /// A word of the script, emphasised where the engine got it wrong.
    struct Piece: Equatable {
        let text: String
        let emphasised: Bool
    }

    /// An expanded line: its script, what the engine heard, and the breakdown.
    struct LineDetail: Equatable {
        let scriptTitle: String
        let script: [Piece]
        let heardTitle: String
        let heard: [TestCallRecord.Heard]
        let summary: String
    }

    /// One row of the Earlier runs sheet.
    struct RunRow: Equatable, Identifiable {
        let id: UUID
        let run: String
        let engine: String
        let wer: String
        /// You, voice A, voice B.
        let roles: [String]
        let clean: String
        let latency: String
        /// The run this window shows, in bold.
        let isThis: Bool
    }

    private enum End {
        case finished
        case slept
    }

    static let finishedHint = "Script finished · press Stop for the score"
    /// Design §3 R12.
    static let sleptHint = "The test call ended when the Mac slept. Press Stop for the score."
    /// Design §5.6.
    static let captureMissing = "The test voices are not being captured; the score will count their lines as missed."
    static let voicesFailed = "The test voices could not play."
    /// Design §3 R20.
    static let interrupted = "No score: the test call did not finish."
    static let unreadable = "Score unavailable: the score file could not be read."
    static let noLinesScored = "No lines were scored."
    static let cleanDefinition = "Clean: one label covers at least 95% of a speaker’s words, and no two speakers"
        + " share it."
    /// Lines shown on each side of the current one.
    private static let shown = 3

    let scenario: TestScenario
    /// Empty when the call is not running in this window.
    let casting: [TestCallRole: CastVoice]
    private(set) var notices: [String] = []
    /// The latest line the conductor announced; 0 before the first.
    private var position = 0
    private var turn: ConductorEvent.Turn?
    private var skipped: Set<Int> = []
    private var end: End?
    /// Set by the window once the controller has read or computed it.
    var score: TestScoreState? {
        didSet { expanded = nil }
    }
    /// The score row open in place, by line number.
    private(set) var expanded: Int?
    /// Nil until loaded; newest first.
    private var runs: [TestRunHistory.Run]?
    private var thisRun: UUID?
    private var runsReadAt = Date.distantPast
    private var timeZone = TimeZone.current

    init(scenario: TestScenario, casting: [TestCallRole: CastVoice]) {
        self.scenario = scenario
        self.casting = casting
    }

    // MARK: - Script

    var title: String { "Script · \(scenario.title)" }

    var progress: String? {
        position > 0 ? "\(position) of \(scenario.lines.count)" : nil
    }

    /// The line being spoken; nil once it is skipped and after the script ends.
    var current: ScriptLine? {
        guard end == nil, position > 0, !skipped.contains(position) else { return nil }
        return line(position)
    }

    /// Up to three lines before the current one, dimmed.
    var earlier: [ScriptLine] {
        let boundary = current == nil ? position + 1 : position
        return (max(1, boundary - Self.shown)..<boundary).map(line)
    }

    var upcoming: [ScriptLine] {
        let first = position + 1
        let last = min(scenario.lines.count, position + Self.shown)
        return first <= last ? (first...last).map(line) : []
    }

    var moreLines: String? {
        let rest = scenario.lines.count - position - upcoming.count
        guard rest > 0 else { return nil }
        return rest == 1 ? "+ 1 more line" : "+ \(rest) more lines"
    }

    var turnTag: TurnTag? {
        guard let current, let turn else { return nil }
        switch turn {
        case .yourTurn:
            return TurnTag(name: "Your turn", detail: "· read this line aloud", isVoice: false)
        case .voiceSpeaking(let role):
            let voice = casting[role].map { "· \($0.voice) voice " } ?? ""
            return TurnTag(name: current.speaker, detail: voice + "· speaking", isVoice: true)
        }
    }

    var hint: String? {
        switch end {
        case .finished: Self.finishedHint
        case .slept: Self.sleptHint
        case nil where current == nil: nil
        case nil: turn == .yourTurn ? "Hands over after a 1.2 s pause" : "Waits for the voice to finish"
        }
    }

    var canSkip: Bool { current != nil }

    // MARK: - Score

    private var record: TestCallRecord? {
        if case .scored(let record)? = score { record } else { nil }
    }

    var scoreTitle: String { record?.scenario.title ?? scenario.title }

    /// Why the head shows no figures (R20).
    var scoreMessage: String? {
        switch score {
        case .missing?: Self.interrupted
        case .unreadable?: Self.unreadable
        case .scored(let record)?: record.lines.contains { $0.status == .done } ? nil : Self.noLinesScored
        case nil: nil
        }
    }

    var overallWER: String { Self.percent(record?.overall.wer) }

    var overallDetail: String {
        guard let overall = record?.overall else { return "" }
        let errors = overall.substitutions + overall.deletions + overall.insertions
        return "word error rate · \(Self.count(errors, "error")) in \(Self.count(overall.words, "word"))"
    }

    var roleRows: [RoleRow] {
        guard let record else { return [] }
        return record.roles.map { role in
            RoleRow(
                role: role.role,
                name: speaker(of: role.role),
                detail: role.role == .you ? "read aloud" : voice(of: role.role, in: record),
                wer: Self.percent(role.counts.wer),
                label: role.majorityLabelName,
                purity: role.purity.map { "\(Int(($0 * 100).rounded()))%" },
                clean: TestCallScorer.isClean(role, among: record.roles)
            )
        }
    }

    var latencyLine: String {
        guard let record else { return "" }
        let latency = record.latency.map {
            "Latency \(Self.seconds($0.median)) median, \(Self.seconds($0.max)) max"
        } ?? "Latency —"
        let scored = record.lines.filter { $0.status == .done }.count
        let crossed = record.crossCredited.voiceWordsAsYou + record.crossCredited.yourWordsAsVoices
        return "\(latency) · \(scored) of \(record.lines.count) lines · cross-credited words: \(crossed)"
    }

    /// Every script line; without a record, the bundled script with no badges.
    var scoreRows: [ScoreRow] {
        guard let record else {
            return scenario.lines.enumerated().map { offset, line in
                ScoreRow(number: offset + 1, role: line.role, speaker: speaker(of: line.role), text: line.text, badges: [])
            }
        }
        return record.lines.map { line in
            ScoreRow(
                number: line.index, role: line.role, speaker: speaker(of: line.role), text: line.reference,
                badges: badges(of: line, in: record)
            )
        }
    }

    /// Only a scored line opens.
    func toggle(_ number: Int) {
        guard self.line(number, in: record)?.status == .done else { return }
        expanded = expanded == number ? nil : number
    }

    var detail: LineDetail? {
        guard let record, let line = self.line(expanded, in: record), let counts = line.counts else { return nil }
        let heard = line.heard ?? []
        let label = line.labels?
            .compactMap { key, words in Int(key).map { (id: $0, words: words) } }
            .min { $0.words != $1.words ? $0.words > $1.words : $0.id < $1.id }
        let heardTitle = ["Heard", label.map { labelName($0.id, in: record) }, line.segmentStart.map(MeetingTime.format)]
            .compactMap { $0 }.joined(separator: " · ")
        var summary = Self.breakdown(counts)
        if let latency = line.latency {
            let after = line.role == .you ? "you stopped speaking" : "the voice ended"
            summary += " · final text \(Self.seconds(latency)) after \(after)"
        }
        return LineDetail(
            scriptTitle: "Script · \(speaker(of: line.role))", script: Self.pieces(of: line.reference, wrong: heard),
            heardTitle: heardTitle, heard: heard, summary: summary
        )
    }

    /// The expanded line's scoring window, whose transcript segments the window highlights.
    var highlight: ClosedRange<Double>? {
        guard let line = self.line(expanded, in: record), let start = line.start, let end = line.end else { return nil }
        return TestCallScorer.window(start: start, end: end)
    }

    // MARK: - Earlier runs

    var runsFooter: String? {
        runs.map { "\(Self.count($0.count, "run")) of this scenario" }
    }

    var runsTitle: String { "Earlier runs · \(scoreTitle)" }

    var runsNote: String {
        let revision = record?.scenario.revision ?? scenario.revision
        return "Revision \(revision) of the scenario, runs on this Mac, newest first. \(Self.cleanDefinition)"
    }

    var runColumns: [String] {
        ["Run", "Engine", "WER", "You", speaker(of: .a), speaker(of: .b), "Clean", "Latency"]
    }

    var runRows: [RunRow] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return (runs ?? []).map { run in
            let record = run.record
            let clean = record.roles.filter { TestCallScorer.isClean($0, among: record.roles) }.count
            return RunRow(
                id: run.id,
                run: Self.when(run.startedAt, now: runsReadAt, calendar: calendar),
                engine: record.engine.title,
                wer: Self.percent(record.overall.wer),
                roles: TestCallRole.allCases.map { role in Self.percent(record.roles.first { $0.role == role }?.counts.wer) },
                clean: "\(clean) of \(record.roles.count)",
                latency: record.latency.map { String(format: "%.1f / %.1f s", $0.median, $0.max) } ?? "—",
                isThis: run.id == thisRun
            )
        }
    }

    /// Runs of this scenario revision, newest first, read when the score appears.
    func showRuns(_ runs: [TestRunHistory.Run], this: UUID?, now: Date, timeZone: TimeZone) {
        self.runs = runs
        thisRun = this
        runsReadAt = now
        self.timeZone = timeZone
    }

    // MARK: - Names

    /// "You", or the role's character as the record or the script names it.
    func speaker(of role: TestCallRole) -> String {
        guard role != .you else { return "You" }
        return record?.voices.first { $0.role == role }?.character
            ?? scenario.voices.first { $0.role == role }?.character
            ?? "Voice \(role.rawValue.uppercased())"
    }

    // MARK: - Inputs

    func apply(_ event: ConductorEvent) {
        switch event {
        case .line(let number, let turn):
            // A line announced just before a sleep arrives after it.
            guard end == nil else { return }
            position = number
            self.turn = turn
        case .skipped(let number, _):
            skipped.insert(number)
        case .captureMissing:
            notice(Self.captureMissing)
        case .voicesFailed:
            notice(Self.voicesFailed)
        case .finished:
            if end == nil { end = .finished }
        }
    }

    /// The meeting paused for sleep, which ended the script (R12).
    func macSlept() {
        if end == nil { end = .slept }
    }

    // MARK: - Score helpers

    private func voice(of role: TestCallRole, in record: TestCallRecord) -> String {
        record.voices.first(where: { $0.role == role }).map { "\($0.voice) voice" } ?? ""
    }

    private func line(_ number: Int?, in record: TestCallRecord?) -> TestCallRecord.Line? {
        record?.lines.first { $0.index == number }
    }

    /// The label's name as recorded for the role it was the majority of, else the engine's.
    private func labelName(_ id: Int, in record: TestCallRecord) -> String {
        record.roles.first { $0.majorityLabel == id }?.majorityLabelName ?? "Speaker \(id)"
    }

    private func badges(of line: TestCallRecord.Line, in record: TestCallRecord) -> [Badge] {
        switch line.status {
        case .skipped: return [Badge(kind: .neutral, text: "Skipped")]
        case .stopped: return [Badge(kind: .neutral, text: "Stopped")]
        case .notReached: return [Badge(kind: .neutral, text: "Not reached")]
        case .done: break
        }
        var badges: [Badge] = []
        let majority = record.roles.first { $0.role == line.role }?.majorityLabel
        let others = (line.labels ?? [:])
            .compactMap { key, words in Int(key).map { (id: $0, words: words) } }
            .filter { $0.id != majority && $0.words > 0 }
            .sorted { $0.id < $1.id }
        if !others.isEmpty {
            let whose = line.role == .you ? "your" : "\(speaker(of: line.role))’s"
            let help = others.map { "\($0.words) of \(whose) words labelled \(labelName($0.id, in: record))" }
            badges.append(Badge(kind: .label, text: "label", help: help.joined(separator: "; ")))
        }
        let errors = line.counts.map { $0.substitutions + $0.deletions + $0.insertions } ?? 0
        badges.append(errors == 0 ? Badge(kind: .ok, text: "✓") : Badge(kind: .errors, text: Self.count(errors, "error")))
        return badges
    }

    /// "2 errors (1 substituted, 1 extra)", or "No errors".
    private static func breakdown(_ counts: TestCallRecord.Counts) -> String {
        let errors = counts.substitutions + counts.deletions + counts.insertions
        guard errors > 0 else { return "No errors" }
        let parts = [(counts.substitutions, "substituted"), (counts.deletions, "missed"), (counts.insertions, "extra")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)" }
        return "\(count(errors, "error")) (\(parts.joined(separator: ", ")))"
    }

    /// The reference's words, with those the engine replaced or missed emphasised, found in order.
    private static func pieces(of reference: String, wrong heard: [TestCallRecord.Heard]) -> [Piece] {
        let words = reference.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let bare = words.map(comparable)
        var emphasised = Set<Int>()
        var cursor = 0
        for entry in heard where entry.op != .match {
            let target = (entry.script ?? "").split(separator: " ").map { comparable(String($0)) }
            guard !target.isEmpty, target.count <= bare.count - cursor,
                  let at = (cursor...(bare.count - target.count)).first(where: {
                      Array(bare[$0..<($0 + target.count)]) == target
                  })
            else { continue }
            emphasised.formUnion(at..<(at + target.count))
            cursor = at + target.count
        }
        return words.indices.map { Piece(text: words[$0], emphasised: emphasised.contains($0)) }
    }

    private static func comparable(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters).lowercased()
    }

    /// "Today 11:14", "9 Nov 16:40", or with the year when it is not this year's.
    private static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
            return "Today " + formatter.string(from: date)
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.dateFormat = sameYear ? "d MMM HH:mm" : "d MMM yyyy HH:mm"
        return formatter.string(from: date)
    }

    /// "6.4%", or "—" without reference words (R15).
    private static func percent(_ rate: Double?) -> String {
        rate.map { String(format: "%.1f%%", $0 * 100) } ?? "—"
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.1f s", value)
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }

    private func notice(_ text: String) {
        if !notices.contains(text) { notices.append(text) }
    }

    private func line(_ number: Int) -> ScriptLine {
        let line = scenario.lines[number - 1]
        return ScriptLine(
            number: number, role: line.role, speaker: speaker(of: line.role), text: line.text,
            skipped: skipped.contains(number)
        )
    }
}
