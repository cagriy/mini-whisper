import Foundation
import MWMeetings
import MWTestCall
import Observation

/// The test call's right-hand pane (design §5.4, mockup `mockup-v5-script-pane.html`): the
/// script during the call, following the conductor's events.
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

    func speaker(of role: TestCallRole) -> String {
        guard role != .you else { return "You" }
        return scenario.voices.first { $0.role == role }?.character ?? "Voice \(role.rawValue.uppercased())"
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
