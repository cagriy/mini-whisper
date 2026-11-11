import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWStreaming
import MWTestCall
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct TestCallPaneModelTests {
    private static let scenario = ScenarioLibrary.scenario(id: "sprint-planning")!
    private static let casting: [TestCallRole: CastVoice] = [
        .a: CastVoice(role: .a, character: "Tom", requested: "Daniel", voice: "Daniel"),
        .b: CastVoice(role: .b, character: "Priya", requested: "Karen", voice: "Karen"),
    ]

    /// The conductor's events up to `last`, the sprint-planning script's turns in order.
    private static func reaching(_ last: Int) -> [ConductorEvent] {
        scenario.lines.prefix(last).enumerated().map { offset, line in
            .line(offset + 1, line.role == .you ? .yourTurn : .voiceSpeaking(line.role))
        }
    }

    private func pane(
        _ events: [ConductorEvent] = [], casting: [TestCallRole: CastVoice] = casting
    ) -> TestCallPaneModel {
        let pane = TestCallPaneModel(scenario: Self.scenario, casting: casting)
        events.forEach(pane.apply)
        return pane
    }

    // MARK: - Script

    @Test func voiceTurnRingsTheLineAndTagsIt() {
        let pane = pane(Self.reaching(1))

        #expect(pane.current?.number == 1)
        #expect(pane.current?.speaker == "Tom")
        #expect(pane.turnTag?.text == "Tom · Daniel voice · speaking")
        #expect(pane.turnTag?.isVoice == true)
        #expect(pane.hint == "Waits for the voice to finish")
        #expect(pane.canSkip)

        var substituted = Self.casting
        substituted[.b]?.voice = "Moira"
        #expect(self.pane(Self.reaching(2), casting: substituted).turnTag?.text == "Priya · Moira voice · speaking")
    }

    @Test func userTurnPromptsAndHints() {
        let pane = pane(Self.reaching(3))

        #expect(pane.current?.number == 3)
        #expect(pane.current?.role == .you)
        #expect(pane.current?.speaker == "You")
        #expect(pane.turnTag?.text == "Your turn · read this line aloud")
        #expect(pane.turnTag?.isVoice == false)
        #expect(pane.hint == "Hands over after a 1.2 s pause")
    }

    @Test func showsUpToThreeEarlierLinesDimmedWithSkipped() {
        #expect(pane(Self.reaching(2)).earlier.map(\.number) == [1])

        let pane = pane(Self.reaching(5) + [.skipped(5, .skipped)])
        // The skipped line leaves the ring before the next line starts.
        #expect(pane.current == nil)
        #expect(pane.canSkip == false)
        #expect(pane.earlier.map(\.number) == [3, 4, 5])
        #expect(pane.earlier.map(\.skipped) == [false, false, true])

        pane.apply(.line(6, .voiceSpeaking(.b)))
        #expect(pane.current?.number == 6)
        #expect(pane.earlier.map(\.number) == [3, 4, 5])
        #expect(pane.earlier.last?.skipped == true)
    }

    @Test func showsTheNextThreeAndTheRestCount() {
        let sixth = pane(Self.reaching(6))
        #expect(sixth.upcoming.map(\.number) == [7, 8, 9])
        #expect(sixth.upcoming.map(\.speaker) == ["Tom", "You", "Priya"])
        #expect(sixth.moreLines == "+ 3 more lines")

        #expect(pane(Self.reaching(8)).moreLines == "+ 1 more line")
        #expect(pane(Self.reaching(10)).upcoming.map(\.number) == [11, 12])
        #expect(pane(Self.reaching(10)).moreLines == nil)

        let before = pane()
        #expect(before.current == nil)
        #expect(before.upcoming.map(\.number) == [1, 2, 3])
        #expect(before.moreLines == "+ 9 more lines")
        #expect(before.hint == nil)
    }

    @Test func headerCountsTheLine() {
        #expect(pane().title == "Script · Sprint planning")
        #expect(pane().progress == nil)
        #expect(pane(Self.reaching(6)).progress == "6 of 12")
    }

    @Test func finishedReadsPressStop() {
        let pane = pane(Self.reaching(12) + [.finished])

        #expect(pane.hint == "Script finished · press Stop for the score")
        #expect(pane.current == nil)
        #expect(pane.canSkip == false)
        #expect(pane.earlier.map(\.number) == [10, 11, 12])
        #expect(pane.upcoming.isEmpty)
        #expect(pane.progress == "12 of 12")
    }

    @Test func sleepShowsTheR12Message() {
        let pane = pane(Self.reaching(6))

        pane.macSlept()

        #expect(pane.hint == "The test call ended when the Mac slept. Press Stop for the score.")
        #expect(pane.current == nil)
        #expect(pane.canSkip == false)
        // A line the conductor announced just before the sleep changes nothing.
        pane.apply(.line(7, .voiceSpeaking(.a)))
        #expect(pane.current == nil)
        #expect(pane.progress == "6 of 12")
    }

    @Test func captureMissingShowsTheCaptureWarning() {
        let pane = pane(Self.reaching(1))
        #expect(pane.notices.isEmpty)

        pane.apply(.captureMissing(1))
        pane.apply(.line(2, .voiceSpeaking(.b)))
        pane.apply(.captureMissing(2))

        #expect(pane.notices == [
            "The test voices are not being captured; the score will count their lines as missed.",
        ])
        #expect(pane.current?.number == 2)
    }

    @Test func voicesFailedShowsTheMessage() {
        let pane = pane(Self.reaching(1) + [
            .skipped(1, .voiceFailed), .line(2, .voiceSpeaking(.b)), .skipped(2, .voiceFailed), .voicesFailed, .finished,
        ])

        #expect(pane.notices == ["The test voices could not play."])
        #expect(pane.hint == "Script finished · press Stop for the score")
        #expect(pane.earlier.map(\.skipped) == [true, true])
    }

    // MARK: - Score

    /// The accepted score mockup as the scorer records it (core `SprintPlanningFixture`): 10 errors
    /// in 157 words on lines 2, 3, 6, 7 and 9, six of Priya's line-9 words under Tom's label, and
    /// line 11 skipped.
    private static let references = [
        "Morning both. Let's keep this to fifteen minutes; the release review starts at half past ten.",
        "Sure. The payments migration is at eighty percent, but the Stripe webhook tests still fail on staging.",
        "I looked at those yesterday. The failures come from the retry header, not the payload, so it's a one-line fix.",
        "Good. Can you pair with Priya on it before Thursday?",
        "Yes, I'll block two hours tomorrow afternoon, from two until four.",
        "Then the remaining risk is the Kubernetes upgrade. It needs a maintenance window of about forty minutes.",
        "Let's ask ops for Wednesday night. Alex, can you send them the runbook?",
        "I'll send it today and copy you both. Version three point two has the rollback steps.",
        "One more thing: design wants the onboarding screens in sprint fourteen, not fifteen.",
        "That's fine if we drop the CSV export. Nobody has asked for it since March.",
        "Agreed. I'll move the export ticket to the backlog and update the board after this call.",
        "Great. Thanks both, see you at the review.",
    ]

    /// Line → (words, S, D, I, start, end, latency); line 11 has none.
    private static let scored: [Int: (Int, Int, Int, Int, Double, Double, Double)] = [
        1: (16, 0, 0, 0, 3.0, 8.6, 1.1), 2: (17, 1, 0, 1, 8.8, 15.2, 1.3), 3: (21, 1, 1, 0, 18.0, 25.6, 1.6),
        4: (10, 0, 0, 0, 27.0, 30.4, 0.9), 5: (11, 0, 0, 0, 34.0, 39.7, 1.2), 6: (17, 1, 0, 1, 41.0, 47.6, 2.9),
        7: (13, 2, 0, 1, 48.8, 54.0, 1.4), 8: (16, 0, 0, 0, 56.0, 62.4, 1.5), 9: (13, 1, 0, 0, 63.7, 69.1, 1.3),
        10: (15, 0, 0, 0, 69.2, 74.6, 1.0), 12: (8, 0, 0, 0, 94.7, 97.5, 0.8),
    ]

    private static let lineSix: [TestCallRecord.Heard] =
        "Then the remaining risk is the".split(separator: " ").map { .init(text: String($0), op: .match) }
            + [.init(text: "Cooper Netties", op: .error, script: "Kubernetes")]
            + "upgrade. It needs a maintenance window of about 40 minutes.".split(separator: " ")
            .map { .init(text: String($0), op: .match) }

    private static func record(
        statuses: [Int: TestCallLineStatus] = [11: .skipped], engine: MeetingEngine = .assemblyaiStreaming
    ) -> TestCallRecord {
        let roles: [TestCallRole] = [.a, .b, .you, .a, .you, .b, .a, .you, .b, .a, .you, .a]
        let label = [TestCallRole.you: "0", .a: "1", .b: "2"]
        let lines = roles.enumerated().map { offset, role in
            let index = offset + 1
            let status = statuses[index] ?? .done
            guard status == .done, let (words, s, d, i, start, end, latency) = scored[index] else {
                return TestCallRecord.Line(index: index, role: role, status: status, reference: references[offset])
            }
            return TestCallRecord.Line(
                index: index, role: role, status: .done, start: start, end: end, overlapped: false,
                reference: references[offset],
                counts: .init(words: words, substitutions: s, deletions: d, insertions: i),
                heard: index == 6 ? lineSix : [],
                labels: index == 9 ? ["1": 6, "2": 7] : [label[role]!: words - d],
                segmentStart: index == 6 ? 41.2 : start + 0.2, latency: latency
            )
        }
        return TestCallRecord(
            scenario: .init(id: "sprint-planning", revision: 1, title: "Sprint planning"),
            engine: engine, overlap: false, scoredAt: Date(timeIntervalSince1970: 1_794_222_962),
            voices: [
                .init(role: .a, character: "Tom", requested: "Daniel", voice: "Daniel"),
                .init(role: .b, character: "Priya", requested: "Karen", voice: "Karen"),
            ],
            lines: lines,
            roles: [
                .init(role: .you, words: 48, substitutions: 1, deletions: 1, insertions: 0,
                      majorityLabel: 0, majorityLabelName: "Alex", purity: 1),
                .init(role: .a, words: 62, substitutions: 2, deletions: 0, insertions: 1,
                      majorityLabel: 1, majorityLabelName: "Speaker 1", purity: 1),
                .init(role: .b, words: 47, substitutions: 3, deletions: 0, insertions: 2,
                      majorityLabel: 2, majorityLabelName: "Speaker 2", purity: 41.0 / 47),
            ],
            overall: .init(words: 157, substitutions: 6, deletions: 1, insertions: 3),
            crossCredited: .init(voiceWordsAsYou: 0, yourWordsAsVoices: 0),
            latency: .init(median: 1.3, max: 2.9, maxLine: 6)
        )
    }

    private func scored(_ record: TestCallRecord = record()) -> TestCallPaneModel {
        let pane = TestCallPaneModel(scenario: Self.scenario, casting: [:])
        pane.score = .scored(record)
        return pane
    }

    @Test func headShowsOverallWERAndErrorCount() {
        let pane = scored()

        #expect(pane.scoreMessage == nil)
        #expect(pane.overallWER == "6.4%")
        #expect(pane.overallDetail == "word error rate · 10 errors in 157 words")
    }

    @Test func roleRowsShowWERLabelAndPurityAmberWhenNotClean() {
        #expect(scored().roleRows == [
            .init(role: .you, name: "You", detail: "read aloud", wer: "4.2%", label: "Alex", purity: "100%", clean: true),
            .init(role: .a, name: "Tom", detail: "Daniel voice", wer: "4.8%", label: "Speaker 1", purity: "100%",
                  clean: true),
            .init(role: .b, name: "Priya", detail: "Karen voice", wer: "10.6%", label: "Speaker 2", purity: "87%",
                  clean: false),
        ])

        var silent = Self.record()
        silent.roles[0] = .init(role: .you, words: 0, substitutions: 0, deletions: 0, insertions: 0)
        let you = scored(silent).roleRows[0]
        #expect(you.wer == "—")
        #expect(you.label == nil)
        #expect(you.purity == nil)
        #expect(you.clean == false)
    }

    @Test func latencyLine() {
        #expect(scored().latencyLine == "Latency 1.3 s median, 2.9 s max · 11 of 12 lines · cross-credited words: 0")

        var crossed = Self.record()
        crossed.crossCredited = .init(voiceWordsAsYou: 2, yourWordsAsVoices: 1)
        crossed.latency = nil
        #expect(scored(crossed).latencyLine == "Latency — · 11 of 12 lines · cross-credited words: 3")
    }

    @Test func lineBadges() {
        let rows = scored(Self.record(statuses: [11: .skipped, 12: .stopped])).scoreRows
        #expect(rows.map(\.number) == Array(1...12))
        #expect(rows[0].badges.map(\.text) == ["✓"])
        #expect(rows[1].badges.map(\.text) == ["2 errors"])
        #expect(rows[6].badges.map(\.text) == ["3 errors"])
        #expect(rows[8].badges.map(\.text) == ["label", "1 error"])
        #expect(rows[8].badges.first?.kind == .label)
        #expect(rows[8].badges.first?.help == "6 of Priya’s words labelled Speaker 1")
        #expect(rows[10].badges.map(\.text) == ["Skipped"])
        #expect(rows[11].badges.map(\.text) == ["Stopped"])
        #expect(rows[5].speaker == "Priya")
        #expect(rows[5].text == Self.references[5])

        let notReached = scored(Self.record(statuses: [11: .stopped, 12: .notReached])).scoreRows
        #expect(notReached[11].badges.map(\.text) == ["Not reached"])
        #expect(notReached[11].badges.map(\.kind) == [.neutral])
        #expect(notReached[0].badges.map(\.kind) == [.ok])
        #expect(notReached[1].badges.map(\.kind) == [.errors])
    }

    @Test func expandedRowText() throws {
        let pane = scored()
        #expect(pane.detail == nil)

        pane.toggle(6)

        #expect(pane.expanded == 6)
        let detail = try #require(pane.detail)
        #expect(detail.scriptTitle == "Script · Priya")
        #expect(detail.script.filter(\.emphasised).map(\.text) == ["Kubernetes"])
        #expect(detail.script.map(\.text).joined(separator: " ") == Self.references[5])
        #expect(detail.heardTitle == "Heard · Speaker 2 · 00:00:41")
        #expect(detail.heard == Self.lineSix)
        #expect(detail.summary == "2 errors (1 substituted, 1 extra) · final text 2.9 s after the voice ended")

        pane.toggle(3)
        #expect(pane.detail?.summary == "2 errors (1 substituted, 1 missed) · final text 1.6 s after you stopped speaking")
        pane.toggle(1)
        #expect(pane.detail?.summary == "No errors · final text 1.1 s after the voice ended")

        pane.toggle(1)
        #expect(pane.expanded == nil)
        pane.toggle(11)
        #expect(pane.expanded == nil)
    }

    @Test func expandingHighlightsSegmentsInTheLinesWindow() {
        let model = MeetingWindowModel(chooser: MeetingWindowModel.Chooser(
            config: Config(), platform: PlatformInfo(osMajor: 26, osMinor: 0), accountName: "Alex", hasKey: { _ in true }
        ))
        model.show(Meeting(title: "Test call · Sprint planning", startedAt: Date(), mode: .remote,
                           engine: .assemblyaiStreaming, userName: "Alex",
                           test: TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")))
        let before = Segment(speaker: 0, start: 34.2, end: 39.5, text: "Yes, I'll block two hours", session: 1)
        let six = Segment(speaker: 2, start: 41.2, end: 47.4, text: "Then the remaining risk", session: 1)
        let seven = Segment(speaker: 1, start: 49.0, end: 53.8, text: "Let's ask ups", session: 1)
        for segment in [before, six, seven] { model.apply(.segmentAdded(segment)) }
        model.apply(.testScore(.scored(Self.record())))
        model.apply(.state(.stopped))
        #expect(model.highlightedSegments.isEmpty)

        model.testCall?.toggle(6)

        #expect(model.testCall?.highlight == 40.5...49.1)
        #expect(model.highlightedSegments == [six.id, seven.id])
        let paragraphs = model.rows.compactMap(\.paragraph)
        #expect(model.highlightedParagraphs == Set(paragraphs.dropFirst().map(\.id)))
    }

    @Test func missingInterruptedUnreadableAndNoLinesMessages() {
        let missing = TestCallPaneModel(scenario: Self.scenario, casting: [:])
        missing.score = .missing
        #expect(missing.scoreMessage == "No score: the test call did not finish.")
        #expect(missing.scoreRows.map(\.text) == Self.scenario.lines.map(\.text))
        #expect(missing.scoreRows.allSatisfy { $0.badges.isEmpty })
        missing.toggle(1)
        #expect(missing.expanded == nil)

        let unreadable = TestCallPaneModel(scenario: Self.scenario, casting: [:])
        unreadable.score = .unreadable
        #expect(unreadable.scoreMessage == "Score unavailable: the score file could not be read.")

        var skipped = Self.record(statuses: Dictionary(uniqueKeysWithValues: (1...12).map { ($0, .skipped) }))
        skipped.overall = .init(words: 0, substitutions: 0, deletions: 0, insertions: 0)
        skipped.latency = nil
        let none = scored(skipped)
        #expect(none.scoreMessage == "No lines were scored.")
        #expect(none.scoreRows.map { $0.badges.map(\.text) } == Array(repeating: ["Skipped"], count: 12))
        #expect(scored().scoreMessage == nil)
    }

    @Test func earlierRunsAreNewestFirstWithThisRunBold() async throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_794_398_400) // 2026-11-11 12:00 UTC
        let this = UUID()
        var enhanced = Self.record(engine: .speechmaticsEnhanced)
        enhanced.latency = nil
        enhanced.roles[2].purity = 0.96
        let runs = [
            TestRunHistory.Run(id: this, startedAt: Date(timeIntervalSince1970: 1_794_395_640), record: Self.record()),
            TestRunHistory.Run(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_794_242_400), record: enhanced),
            TestRunHistory.Run(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_793_956_320), record: Self.record()),
            TestRunHistory.Run(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_762_074_300), record: Self.record()),
        ]
        let pane = scored()
        #expect(pane.runsFooter == nil)

        pane.showRuns(runs, this: this, now: now, timeZone: utc)

        #expect(pane.runsFooter == "4 runs of this scenario")
        #expect(pane.runsTitle == "Earlier runs · Sprint planning")
        #expect(pane.runsNote == "Revision 1 of the scenario, runs on this Mac, newest first. Clean: one label covers"
            + " at least 95% of a speaker’s words, and no two speakers share it.")
        #expect(pane.runColumns == ["Run", "Engine", "WER", "You", "Tom", "Priya", "Clean", "Latency"])
        #expect(pane.runRows.map(\.isThis) == [true, false, false, false])
        #expect(pane.runRows.map(\.run) == ["Today 11:14", "9 Nov 16:40", "6 Nov 09:12", "2 Nov 2025 09:05"])
        #expect(pane.runRows[0].engine == "AssemblyAI Universal-Streaming")
        #expect(pane.runRows[0].wer == "6.4%")
        #expect(pane.runRows[0].roles == ["4.2%", "4.8%", "10.6%"])
        #expect(pane.runRows[0].clean == "2 of 3")
        #expect(pane.runRows[0].latency == "1.3 / 2.9 s")
        #expect(pane.runRows[1].engine == "Speechmatics Enhanced")
        #expect(pane.runRows[1].clean == "3 of 3")
        #expect(pane.runRows[1].latency == "—")

        pane.showRuns(Array(runs.prefix(1)), this: this, now: now, timeZone: utc)
        #expect(pane.runsFooter == "1 run of this scenario")
    }

    @Test func windowModelLoadsTheTagsRunsForThePane() async throws {
        var asked: [TestCallTag] = []
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_794_398_400)
        let model = MeetingWindowModel(
            chooser: MeetingWindowModel.Chooser(
                config: Config(), platform: PlatformInfo(osMajor: 26, osMinor: 0), accountName: "Alex",
                hasKey: { _ in true }
            ),
            timeZone: try #require(TimeZone(identifier: "UTC")),
            now: { now },
            loadRuns: { tag in
                asked.append(tag)
                return [TestRunHistory.Run(id: id, startedAt: Date(timeIntervalSince1970: 1_794_395_640), record: Self.record())]
            }
        )
        let tag = TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning", wer: 0.064)
        model.show(Meeting(id: id, title: "Test call · Sprint planning", startedAt: Date(), mode: .remote,
                           engine: .assemblyaiStreaming, userName: "Alex", test: tag))
        model.apply(.testScore(.scored(Self.record())))

        await model.loadEarlierRuns()

        #expect(asked == [tag])
        #expect(model.testCall?.runRows.map(\.run) == ["Today 11:14"])
        #expect(model.testCall?.runRows.map(\.isThis) == [true])
    }

    @Test func scoreArrivingBeforeTheMeetingReachesThePane() {
        let model = MeetingWindowModel(chooser: MeetingWindowModel.Chooser(
            config: Config(), platform: PlatformInfo(osMajor: 26, osMinor: 0), accountName: "Alex", hasKey: { _ in true }
        ))
        model.apply(.testScore(.missing))
        model.show(Meeting(title: "Test call · Sprint planning", startedAt: Date(), mode: .remote,
                           engine: .assemblyaiStreaming, userName: "Alex",
                           test: TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")))

        #expect(model.testCall?.score == .missing)
        model.apply(.testScore(.unreadable))
        #expect(model.testCall?.score == .unreadable)
    }
}
