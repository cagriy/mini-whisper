import Foundation
import MWMeetings
import Testing

import MWTestCall

private typealias Counts = TestCallRecord.Counts
private typealias Heard = TestCallRecord.Heard
private typealias RoleScore = TestCallRecord.RoleScore

private let scoredAt = Date(timeIntervalSince1970: 1_794_000_000)

@Suite struct TestCallScorerTests {
    @Test func perfectTranscriptScoresZero() {
        let record = score(SprintPlanningFixture.input(perfect: true))

        #expect(record.overall == Counts(words: 157, substitutions: 0, deletions: 0, insertions: 0))
        #expect(record.overall.wer == 0)
        #expect(record.roles.map(\.counts.wer) == [0, 0, 0])
        #expect(record.roles.map(\.purity) == [1, 1, 1])
        #expect(record.roles.filter { TestCallScorer.isClean($0, among: record.roles) }.count == 3)
        #expect(record.lines.compactMap(\.heard).joined().allSatisfy { $0.op == .match })
    }

    @Test func mockupCaseMatchesTheAcceptedFigures() throws {
        let record = score(SprintPlanningFixture.input())

        #expect(record.scenario == .init(id: "sprint-planning", revision: 1, title: "Sprint planning"))
        #expect(record.engine == .assemblyaiStreaming)
        #expect(record.overlap == false)
        #expect(record.scoredAt == scoredAt)
        #expect(record.voices == [
            .init(role: .a, character: "Tom", requested: "Daniel", voice: "Daniel"),
            .init(role: .b, character: "Priya", requested: "Karen", voice: "Karen"),
        ])

        // R14 splits the script's "one-line" into two words, so line 3 has 21 and the call 157; the
        // mockup's placeholder shows 156 words, You 4.3% (planning decision 18).
        #expect(record.overall == Counts(words: 157, substitutions: 6, deletions: 1, insertions: 3))
        #expect(percent(record.overall.wer) == "6.4")
        let errors = record.lines.filter { $0.status == .done }.map { line in
            line.counts.map { $0.substitutions + $0.deletions + $0.insertions }
        }
        #expect(errors == [0, 2, 2, 0, 0, 2, 3, 0, 1, 0, 0])

        #expect(record.roles.map(\.role) == [.you, .a, .b])
        let (you, tom, priya) = (record.roles[0], record.roles[1], record.roles[2])
        #expect(you.counts == Counts(words: 48, substitutions: 1, deletions: 1, insertions: 0))
        #expect(tom.counts == Counts(words: 62, substitutions: 2, deletions: 0, insertions: 1))
        #expect(priya.counts == Counts(words: 47, substitutions: 3, deletions: 0, insertions: 2))
        #expect([you, tom, priya].map { percent($0.counts.wer) } == ["4.2", "4.8", "10.6"])
        #expect([you, tom, priya].map(\.majorityLabel) == [0, 1, 2])
        #expect([you, tom, priya].map(\.majorityLabelName) == ["Alex", "Speaker 1", "Speaker 2"])
        // Labels count the transcript words aligned to script words: Priya's 47, 6 of them under
        // Speaker 1. Her inserted "hook" and "Netties" carry no label.
        #expect([you, tom].map(\.purity) == [1, 1])
        #expect(priya.purity == 41.0 / 47.0)
        #expect(String(format: "%.0f", try #require(priya.purity) * 100) == "87")
        #expect(record.roles.map { TestCallScorer.isClean($0, among: record.roles) } == [true, true, false])
        #expect(record.crossCredited == .init(voiceWordsAsYou: 0, yourWordsAsVoices: 0))

        let latency = try #require(record.latency)
        #expect(abs(latency.median - 1.3) < 1e-9)
        #expect(abs(latency.max - 2.9) < 1e-9)
        #expect(latency.maxLine == 6)
        #expect(record.lines.count == 12)
        #expect(record.lines.filter { $0.status == .done }.count == 11)

        let line6 = record.lines[5]
        #expect(line6.index == 6)
        #expect(line6.counts == Counts(words: 17, substitutions: 1, deletions: 0, insertions: 1))
        #expect(line6.heard == matched("Then the remaining risk is the")
            + [Heard(text: "Cooper Netties", op: .error, script: "Kubernetes")]
            + matched("upgrade. It needs a maintenance window of about 40 minutes."))
        #expect(abs(try #require(line6.segmentStart) - 41.2) < 1e-9)
        #expect(line6.labels == ["2": 17])
        #expect(abs(try #require(line6.latency) - 2.9) < 1e-9)
        #expect(record.lines[8].labels == ["1": 6, "2": 7])
    }

    @Test func overlappingWindowsResolveByTokenMatch() {
        // Windows [-0.5, 3.5] and [2.0, 6.0] overlap.
        let record = score(
            run([
                RunLine(index: 1, role: .a, status: .done, start: 0, end: 2),
                RunLine(index: 2, role: .b, status: .done, start: 2.5, end: 4.5),
            ]),
            scenario([(.a, "alpha bravo the"), (.b, "the charlie delta")]),
            [segment(1, [
                ("alpha", 0.4), ("bravo", 1.0),
                ("the", 2.1),  // both lines hold an unconsumed "the": the earlier line
                ("zulu", 2.2),  // neither holds it: line 1's span is 0.2 s away, line 2's 0.3 s
                ("yankee", 2.35),  // line 2's span is nearer
                ("the", 2.6),  // line 1's "the" is consumed
                ("charlie", 3.0), ("delta", 3.3),
            ])]
        )

        #expect(record.lines[0].heard == matched("alpha bravo the") + [Heard(text: "zulu", op: .error, script: "")])
        #expect(record.lines[1].heard == [Heard(text: "yankee", op: .error, script: "")] + matched("the charlie delta"))
        #expect(record.overall == Counts(words: 6, substitutions: 0, deletions: 0, insertions: 2))
    }

    @Test func wordsOutsideEveryWindowAreIgnored() {
        let record = score(
            run([
                RunLine(index: 1, role: .a, status: .done, start: 10, end: 12),
                RunLine(index: 2, role: .you, status: .skipped, start: 18, end: 21, skipReason: .skipped),
                RunLine(index: 3, role: .b, status: .done, start: 30, end: 32),
            ]),
            scenario([(.a, "alpha bravo"), (.you, "charlie delta"), (.b, "echo foxtrot")]),
            [
                // Line 1's window is [9.5, 13.5].
                segment(1, [("early", 9.4), ("um", 9.6), ("alpha", 10.5), ("bravo", 11.5), ("uh", 13.4), ("late", 13.6)]),
                segment(0, [("charlie", 18.5), ("delta", 19.5)]),
                segment(2, [("echo", 30.5), ("foxtrot", 31.5), ("after", 40)]),
            ]
        )

        #expect(record.lines[0].heard?.compactMap(\.text) == ["um", "alpha", "bravo", "uh"])
        #expect(record.lines[1].heard == nil)
        #expect(record.lines[2].heard == matched("echo foxtrot"))
        #expect(record.overall == Counts(words: 4, substitutions: 0, deletions: 0, insertions: 2))
        #expect(record.roles[0].purity == nil)
    }

    @Test func segmentsWithoutWordTimingsSpreadTokensEvenly() {
        let untimed = Segment(speaker: 1, start: 0, end: 8, text: "Alpha bravo, charlie delta.", session: 1)

        // Four tokens over [0, 8] sit at 1, 3, 5 and 7; the windows are [0, 4.5] and [4.5, 9].
        let record = score(
            run([
                RunLine(index: 1, role: .a, status: .done, start: 0.5, end: 3),
                RunLine(index: 2, role: .b, status: .done, start: 5, end: 7.5),
            ]),
            scenario([(.a, "alpha bravo"), (.b, "charlie delta")]),
            [untimed],
            arrivals: [untimed.id: 9]
        )

        #expect(record.lines.map(\.heard) == [matched("Alpha bravo,"), matched("charlie delta.")])
        #expect(record.lines.map(\.segmentStart) == [0, 0])
        #expect(record.lines.map(\.latency) == [6, 1.5])
    }

    @Test func skippedStoppedAndNotReachedLinesAreExcludedButKeepTheirReference() {
        let record = score(
            run([
                RunLine(index: 1, role: .a, status: .done, start: 0, end: 2),
                RunLine(index: 2, role: .you, status: .skipped, skipReason: .noSpeech),
                RunLine(index: 3, role: .b, status: .stopped, start: 25),
                RunLine(index: 4, role: .a),
            ]),
            scenario([(.a, "alpha bravo"), (.you, "charlie delta"), (.b, "echo foxtrot"), (.a, "golf hotel")]),
            [segment(1, [("alpha", 0.5), ("bravo", 1.5)]), segment(2, [("echo", 25.5)])]
        )

        #expect(record.lines.map(\.index) == [1, 2, 3, 4])
        #expect(record.lines.map(\.status) == [.done, .skipped, .stopped, .notReached])
        #expect(record.lines.map(\.reference) == ["alpha bravo", "charlie delta", "echo foxtrot", "golf hotel"])
        #expect(record.lines[2].start == 25)
        let unscored = record.lines.dropFirst()
        #expect(unscored.allSatisfy { $0.counts == nil && $0.heard == nil && $0.labels == nil })
        #expect(unscored.allSatisfy { $0.segmentStart == nil && $0.latency == nil })
        #expect(record.overall == Counts(words: 2, substitutions: 0, deletions: 0, insertions: 0))
        #expect(record.roles.map(\.words) == [0, 2, 0])
    }

    @Test func zeroScoredLinesGivesAnEmptyScore() {
        var input = SprintPlanningFixture.input()
        for index in input.run.lines.indices {
            input.run.lines[index].status = .skipped
            input.run.lines[index].skipReason = .skipped
        }

        let record = score(input)

        #expect(record.overall == Counts(words: 0, substitutions: 0, deletions: 0, insertions: 0))
        #expect(record.overall.wer == nil)
        #expect(record.latency == nil)
        #expect(record.lines.map(\.reference) == SprintPlanningFixture.scenario.lines.map(\.text))
        #expect(record.lines.allSatisfy { $0.counts == nil })
        #expect(record.roles == [TestCallRole.you, .a, .b].map {
            RoleScore(role: $0, words: 0, substitutions: 0, deletions: 0, insertions: 0)
        })
        #expect(record.crossCredited == .init(voiceWordsAsYou: 0, yourWordsAsVoices: 0))
    }

    @Test func crossCreditedCounts() {
        let record = score(
            run([
                RunLine(index: 1, role: .a, status: .done, start: 0, end: 3),
                RunLine(index: 2, role: .you, status: .done, start: 5, end: 7),
            ]),
            scenario([(.a, "alpha bravo charlie"), (.you, "delta echo")]),
            [
                segment(1, [("alpha", 0.5)]),
                // "extra" is no script word, so its label counts for nothing.
                segment(0, [("bravo", 1.5), ("charlie", 2.5), ("extra", 2.8)]),
                segment(0, [("delta", 5.5)]),
                segment(2, [("echo", 6.5)]),
            ]
        )

        #expect(record.crossCredited == .init(voiceWordsAsYou: 2, yourWordsAsVoices: 1))
        #expect(record.lines.map(\.labels) == [["0": 2, "1": 1], ["0": 1, "2": 1]])
        let (you, voice) = (record.roles[0], record.roles[1])
        #expect(voice.majorityLabel == 0)
        #expect(voice.purity == 2.0 / 3.0)
        // A 1–1 tie goes to the lower speaker id.
        #expect(you.majorityLabel == 0)
        #expect(you.majorityLabelName == "Alex")
        #expect(you.purity == 0.5)
    }

    @Test func cleanNeedsPurityAndALabelNoOtherRoleHas() {
        func role(_ role: TestCallRole, label: Int?, purity: Double?) -> RoleScore {
            RoleScore(role: role, words: 20, substitutions: 0, deletions: 0, insertions: 0, majorityLabel: label, purity: purity)
        }
        let you = role(.you, label: 0, purity: 1)
        let a = role(.a, label: 1, purity: 0.95)

        #expect(TestCallScorer.isClean(you, among: [you, a]))
        #expect(TestCallScorer.isClean(a, among: [you, a]))
        #expect(!TestCallScorer.isClean(a, among: [you, a, role(.b, label: 1, purity: 1)]))
        #expect(!TestCallScorer.isClean(role(.b, label: 2, purity: 0.94), among: [you, a]))
        #expect(!TestCallScorer.isClean(role(.b, label: nil, purity: nil), among: [you, a]))
    }

    @Test func missedScriptWordsAppearAsMissedEntries() {
        let record = score(
            run([RunLine(index: 1, role: .a, status: .done, start: 0, end: 4)]),
            scenario([(.a, "Please send the new runbook today.")]),
            [segment(1, [("Please", 0.5), ("send", 1.0), ("runbook", 2.0), ("today.", 3.0)])]
        )

        #expect(record.lines[0].heard == matched("Please send")
            + [Heard(op: .missed, script: "the"), Heard(op: .missed, script: "new")]
            + matched("runbook today."))
        #expect(record.lines[0].counts == Counts(words: 6, substitutions: 0, deletions: 2, insertions: 0))
    }

    @Test func aRunOfErrorWordsJoinsTheScriptWordsItReplaced() {
        let record = score(
            run([RunLine(index: 1, role: .a, status: .done, start: 0, end: 4)]),
            scenario([(.a, "Please send the runbook.")]),
            [segment(1, [("Please", 0.5), ("sent", 1.0), ("a", 1.5), ("run", 2.0), ("book.", 2.5)])]
        )

        #expect(record.lines[0].heard == matched("Please")
            + [Heard(text: "sent a run book.", op: .error, script: "send the runbook.")])
        #expect(record.lines[0].counts == Counts(words: 4, substitutions: 3, deletions: 0, insertions: 1))
    }
}

private func score(_ input: SprintPlanningFixture.Input) -> TestCallRecord {
    score(input.run, SprintPlanningFixture.scenario, input.segments, arrivals: input.arrivals)
}

private func score(
    _ run: TestCallRun, _ scenario: TestScenario, _ segments: [Segment], arrivals: [UUID: Double] = [:]
) -> TestCallRecord {
    TestCallScorer().score(
        run: run, scenario: scenario, segments: segments, arrivals: arrivals,
        speakers: SprintPlanningFixture.speakers, userSpeaker: SprintPlanningFixture.alex,
        engine: .assemblyaiStreaming, scoredAt: scoredAt
    )
}

private func run(_ lines: [RunLine]) -> TestCallRun {
    TestCallRun(lines: lines, casting: SprintPlanningFixture.casting, overlap: false)
}

private func scenario(_ lines: [(TestCallRole, String)]) -> TestScenario {
    TestScenario(
        id: "scorer", revision: 1, title: "Scorer", voices: [],
        lines: lines.map { ScenarioLine(role: $0.0, text: $0.1) }
    )
}

/// One segment of words centred on the given meeting seconds.
private func segment(_ speaker: Int, _ words: [(String, Double)]) -> Segment {
    let timed = words.map { Word(text: $0.0, start: $0.1 - 0.05, end: $0.1 + 0.05) }
    return Segment(
        speaker: speaker, start: timed[0].start, end: timed[timed.count - 1].end,
        text: words.map(\.0).joined(separator: " "), words: timed, session: 1
    )
}

private func matched(_ text: String) -> [Heard] {
    text.split(separator: " ").map { Heard(text: String($0), op: .match) }
}

private func percent(_ rate: Double?) -> String? {
    rate.map { String(format: "%.1f", $0 * 100) }
}
