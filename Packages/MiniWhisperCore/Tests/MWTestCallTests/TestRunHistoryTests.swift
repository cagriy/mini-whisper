import Foundation
import MWConfig
import MWMeetings
import Testing

import MWTestCall

@Suite struct TestRunHistoryTests {
    private struct LoadFailed: Error {}

    private let sprint = TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")

    private func entry(_ tag: TestCallTag?, at seconds: TimeInterval, wer: Double? = nil) -> IndexEntry {
        var tag = tag
        tag?.wer = wer
        return IndexEntry(
            id: UUID(), title: "Test call", startedAt: Date(timeIntervalSince1970: seconds), endedAt: nil,
            duration: 120, mode: .remote, app: nil, engine: .assemblyaiStreaming, speakerCount: 3,
            costUSD: 0.02, hasSummary: false, audioBytes: 0, excerpt: "", test: tag
        )
    }

    private func record(for entry: IndexEntry) -> TestCallRecord {
        TestCallRecord(
            scenario: .init(id: "sprint-planning", revision: 1, title: "Sprint planning"),
            engine: entry.engine, overlap: false, scoredAt: entry.startedAt, voices: [], lines: [], roles: [],
            overall: .init(words: 0, substitutions: 0, deletions: 0, insertions: 0),
            crossCredited: .init(voiceWordsAsYou: 0, yourWordsAsVoices: 0), latency: nil
        )
    }

    @Test func latestWERIsTheNewestScoredRunOfTheCurrentRevision() {
        let incident = TestCallTag(scenarioID: "incident-review", revision: 1, scenarioTitle: "Incident review")
        let retired = TestCallTag(scenarioID: "retired", revision: 1, scenarioTitle: "Retired")
        var sprintRevision2 = sprint
        sprintRevision2.revision = 2
        let index = [
            entry(sprintRevision2, at: 100, wer: 0.10),
            entry(sprint, at: 500, wer: 0.50),
            entry(sprintRevision2, at: 400),
            entry(nil, at: 600),
            entry(sprintRevision2, at: 300, wer: 0.064),
            entry(incident, at: 50, wer: 0.20),
            entry(retired, at: 700, wer: 0.30),
        ]

        let latest = TestRunHistory.latestWER(in: index, revisions: ["sprint-planning": 2, "incident-review": 1])

        #expect(latest == ["sprint-planning": 0.064, "incident-review": 0.20])
    }

    @Test func runsAreTheSameIDAndRevisionNewestFirst() {
        var sprintRevision2 = sprint
        sprintRevision2.revision = 2
        let incident = TestCallTag(scenarioID: "incident-review", revision: 1, scenarioTitle: "Incident review")
        let index = [
            entry(sprint, at: 100, wer: 0.1),
            entry(sprint, at: 300),
            entry(sprintRevision2, at: 400, wer: 0.2),
            entry(sprint, at: 200, wer: 0.3),
            entry(incident, at: 500, wer: 0.4),
            entry(nil, at: 600),
        ]
        let records = Dictionary(uniqueKeysWithValues: index.map { ($0.id, record(for: $0)) })

        let runs = TestRunHistory.runs(of: sprint, in: index, load: { records[$0] })

        #expect(runs.map(\.id) == [index[1].id, index[3].id, index[0].id])
        #expect(runs.map(\.startedAt) == [300, 200, 100].map { Date(timeIntervalSince1970: $0) })
        #expect(runs.map(\.record) == [index[1], index[3], index[0]].map(record(for:)))
    }

    @Test func runsAreCappedAtFifty() {
        let index = (1...60).map { entry(sprint, at: TimeInterval($0), wer: 0.1) }
        var loads = 0

        let runs = TestRunHistory.runs(of: sprint, in: index) { id in
            loads += 1
            return index.first { $0.id == id }.map(record(for:))
        }

        #expect(runs.count == 50)
        #expect(loads == 50)
        #expect(runs.first?.startedAt == Date(timeIntervalSince1970: 60))
        #expect(runs.last?.startedAt == Date(timeIntervalSince1970: 11))
    }

    @Test func runsSkipEntriesWhoseRecordIsMissing() {
        let index = [entry(sprint, at: 100, wer: 0.1), entry(sprint, at: 200), entry(sprint, at: 300, wer: 0.2)]

        let runs = TestRunHistory.runs(of: sprint, in: index) { id in
            switch id {
            case index[0].id: return record(for: index[0])
            case index[1].id: return nil
            default: throw LoadFailed()
            }
        }

        #expect(runs.map(\.id) == [index[0].id])
    }
}
