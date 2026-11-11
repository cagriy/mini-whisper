import Foundation
import MWMeetings

import MWTestCall

/// The accepted score mockup (`mockup-v5-pane-score.html`) as scorer input, built line by line from
/// its badges and heard text:
/// - lines 2, 3, 6, 7 and 9 carry the 10 errors (6 S, 1 D, 3 I);
/// - line 9's first 6 words carry Tom's label;
/// - line 11 is skipped for silence;
/// - line 6's final text arrives 2.9 s after the voice ended, and the median latency is 1.3 s.
enum SprintPlanningFixture {
    static let alex = 0
    static let speaker1 = 1
    static let speaker2 = 2

    static let scenario = TestScenario(
        id: "sprint-planning", revision: 1, title: "Sprint planning",
        voices: [
            VoiceRole(role: .a, character: "Tom", requested: "Daniel"),
            VoiceRole(role: .b, character: "Priya", requested: "Karen"),
        ],
        lines: [
            ScenarioLine(role: .a, text: "Morning both. Let's keep this to fifteen minutes; the release review starts at half past ten."),
            ScenarioLine(role: .b, text: "Sure. The payments migration is at eighty percent, but the Stripe webhook tests still fail on staging."),
            ScenarioLine(role: .you, text: "I looked at those yesterday. The failures come from the retry header, not the payload, so it's a one-line fix."),
            ScenarioLine(role: .a, text: "Good. Can you pair with Priya on it before Thursday?"),
            ScenarioLine(role: .you, text: "Yes, I'll block two hours tomorrow afternoon, from two until four."),
            ScenarioLine(role: .b, text: "Then the remaining risk is the Kubernetes upgrade. It needs a maintenance window of about forty minutes."),
            ScenarioLine(role: .a, text: "Let's ask ops for Wednesday night. Alex, can you send them the runbook?"),
            ScenarioLine(role: .you, text: "I'll send it today and copy you both. Version three point two has the rollback steps."),
            ScenarioLine(role: .b, text: "One more thing: design wants the onboarding screens in sprint fourteen, not fifteen."),
            ScenarioLine(role: .a, text: "That's fine if we drop the CSV export. Nobody has asked for it since March."),
            ScenarioLine(role: .you, text: "Agreed. I'll move the export ticket to the backlog and update the board after this call."),
            ScenarioLine(role: .a, text: "Great. Thanks both, see you at the review."),
        ]
    )

    static let speakers = [
        SpeakerLabel(id: alex, name: "Alex", isUser: true),
        SpeakerLabel(id: speaker1, name: "Speaker 1"),
        SpeakerLabel(id: speaker2, name: "Speaker 2"),
    ]

    static let casting: [TestCallRole: CastVoice] = [
        .a: CastVoice(role: .a, character: "Tom", requested: "Daniel", voice: "Daniel"),
        .b: CastVoice(role: .b, character: "Priya", requested: "Karen", voice: "Karen"),
    ]

    struct Input {
        var run: TestCallRun
        var segments: [Segment]
        var arrivals: [UUID: Double]
    }

    /// A `done` line: its run times, the engine's segments for it, and when its last segment arrived.
    private struct Spoken {
        var start: Double
        var end: Double
        var heard: [(speaker: Int, text: String)]
        var latency: Double
    }

    /// By line number; line 11 has no entry. Line 6's times and segment start are the design's §5.2
    /// example; adjacent windows overlap at lines 1–2 and 9–10.
    private static let spoken: [Int: Spoken] = [
        1: Spoken(start: 3.0, end: 8.6, heard: [(speaker1, "Morning both. Let's keep this to 15 minutes; the release review starts at half past 10.")], latency: 1.1),
        2: Spoken(start: 8.8, end: 15.2, heard: [(speaker2, "Sure. The payments migration is at 80%, but the Stripe web hook tests still fail on staging.")], latency: 1.3),
        3: Spoken(start: 18.0, end: 25.6, heard: [(alex, "I looked at those yesterday. The failures come from the retry header, not the payload, so its one-line fix.")], latency: 1.6),
        4: Spoken(start: 27.0, end: 30.4, heard: [(speaker1, "Good. Can you pair with Priya on it before Thursday?")], latency: 0.9),
        5: Spoken(start: 34.0, end: 39.7, heard: [(alex, "Yes, I'll block two hours tomorrow afternoon, from 2 until 4.")], latency: 1.2),
        6: Spoken(start: 41.0, end: 47.6, heard: [(speaker2, "Then the remaining risk is the Cooper Netties upgrade. It needs a maintenance window of about 40 minutes.")], latency: 2.9),
        7: Spoken(start: 48.8, end: 54.0, heard: [(speaker1, "Let's ask ups for Wednesday night. Alex, can you send them the run book?")], latency: 1.4),
        8: Spoken(start: 56.0, end: 62.4, heard: [(alex, "I'll send it today and copy you both. Version 3.2 has the rollback steps.")], latency: 1.5),
        9: Spoken(start: 63.7, end: 69.1, heard: [(speaker1, "One more thing: design wants the"), (speaker2, "onboarding screens in sprint 40, not 15.")], latency: 1.3),
        10: Spoken(start: 69.2, end: 74.6, heard: [(speaker1, "That's fine if we drop the CSV export. Nobody has asked for it since March.")], latency: 1.0),
        12: Spoken(start: 94.7, end: 97.5, heard: [(speaker1, "Great. Thanks both, see you at the review.")], latency: 0.8),
    ]

    /// `perfect` replaces each line's heard text with its script, under the role's own label.
    static func input(perfect: Bool = false) -> Input {
        var lines: [RunLine] = []
        var segments: [Segment] = []
        var arrivals: [UUID: Double] = [:]
        for (offset, line) in scenario.lines.enumerated() {
            let index = offset + 1
            guard let spoken = spoken[index] else {
                lines.append(RunLine(index: index, role: line.role, status: .skipped, skipReason: .noSpeech))
                continue
            }
            lines.append(RunLine(index: index, role: line.role, status: .done, start: spoken.start, end: spoken.end))

            let label = [TestCallRole.you: alex, .a: speaker1, .b: speaker2][line.role]!
            let heard = perfect ? [(speaker: label, text: line.text)] : spoken.heard
            // Words spread evenly over the line, 0.2 s in from each end.
            let first = spoken.start + 0.2
            let step = (spoken.end - 0.2 - first) / Double(heard.map { $0.text.split(separator: " ").count }.reduce(0, +))
            var position = 0
            for (part, (speaker, text)) in heard.enumerated() {
                let words = text.split(separator: " ").map { word in
                    defer { position += 1 }
                    return Word(text: String(word), start: first + Double(position) * step, end: first + Double(position + 1) * step)
                }
                let segment = Segment(speaker: speaker, start: words[0].start, end: words[words.count - 1].end, text: text, words: words, session: 1)
                segments.append(segment)
                arrivals[segment.id] = part == heard.count - 1 ? spoken.end + spoken.latency : segment.end + 0.5
            }
        }
        return Input(run: TestCallRun(lines: lines, casting: casting, overlap: false), segments: segments, arrivals: arrivals)
    }
}
