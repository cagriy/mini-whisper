import Foundation
import MWConfig
import Testing

import MWCorrections

/// R2: how often a phrase has been corrected, capped at 200.
@Suite struct CorrectionTallyTests {
    private static let now = Date(timeIntervalSince1970: 1_757_000_000)

    private static func entry(
        _ heard: String,
        count: Int,
        last: TimeInterval
    ) -> CorrectionTallyEntry {
        CorrectionTallyEntry(heard: heard, count: count, last: Date(timeIntervalSince1970: last))
    }

    @Test func aFirstIncrementCreatesAnEntry() {
        let tally = CorrectionTally.incremented([], heard: "  eefa ", now: Self.now)

        #expect(tally == [CorrectionTallyEntry(heard: "eefa", count: 1, last: Self.now)])
    }

    @Test func anotherSpellingOfTheSamePhraseRaisesTheCountAndKeepsTheFirstSpelling() {
        let first = CorrectionTally.incremented([], heard: "Get Hub", now: Self.now)

        let tally = CorrectionTally.incremented(
            first, heard: "get hub", now: Self.now.addingTimeInterval(60)
        )

        #expect(
            tally == [
                CorrectionTallyEntry(
                    heard: "Get Hub", count: 2, last: Self.now.addingTimeInterval(60)
                )
            ]
        )
    }

    @Test func theTwoHundredAndFirstPhraseEvictsTheLowestCount() {
        var full = (0..<200).map { Self.entry("phrase \($0)", count: 5, last: 1_000) }
        full[42] = Self.entry("weakest", count: 1, last: 9_000)

        let tally = CorrectionTally.incremented(full, heard: "new", now: Self.now)

        #expect(tally.count == 200)
        #expect(!tally.contains { $0.heard == "weakest" })
        #expect(tally.last == CorrectionTallyEntry(heard: "new", count: 1, last: Self.now))
    }

    @Test func amongEqualCountsTheOldestEntryIsEvicted() {
        var full = (0..<200).map { Self.entry("phrase \($0)", count: 5, last: 1_000) }
        full[7] = Self.entry("oldest", count: 2, last: 100)
        full[9] = Self.entry("newer", count: 2, last: 200)

        let tally = CorrectionTally.incremented(full, heard: "new", now: Self.now)

        #expect(!tally.contains { $0.heard == "oldest" })
        #expect(tally.contains { $0.heard == "newer" })
    }

    @Test func anExistingPhraseNeverEvictsAtTheCap() {
        let full = (0..<200).map { Self.entry("phrase \($0)", count: 5, last: 1_000) }

        let tally = CorrectionTally.incremented(full, heard: "phrase 3", now: Self.now)

        #expect(tally.count == 200)
        #expect(tally[3] == CorrectionTallyEntry(heard: "phrase 3", count: 6, last: Self.now))
    }

    @Test func topOrdersByCountThenMostRecent() {
        let tally = [
            Self.entry("one", count: 2, last: 500),
            Self.entry("two", count: 9, last: 100),
            Self.entry("three", count: 2, last: 900),
            Self.entry("four", count: 4, last: 100),
            Self.entry("five", count: 1, last: 100),
            Self.entry("six", count: 1, last: 200),
        ]

        let rows = CorrectionTally.top(tally, limit: 5, rules: [])

        #expect(rows.map(\.heard) == ["two", "four", "three", "one", "six"])
        #expect(rows.map(\.count) == [9, 4, 2, 2, 1])
    }

    @Test func hasRuleCoversAnEnabledRulesHeardAndItsSoundsLike() {
        let tally = [
            Self.entry("Get Hub", count: 3, last: 100),
            Self.entry("eva", count: 2, last: 100),
            Self.entry("speech matics", count: 1, last: 100),
        ]
        let rules = [
            CorrectionRule(heard: "get hub", write: "GitHub"),
            CorrectionRule(heard: "eefa", write: "Aoife", soundsLike: ["eva"]),
        ]

        let rows = CorrectionTally.top(tally, limit: 5, rules: rules)

        #expect(rows.map(\.hasRule) == [true, true, false])
    }

    @Test func aDisabledRuleDoesNotCountAsRemembered() {
        var disabled = CorrectionRule(heard: "get hub", write: "GitHub")
        disabled.enabled = false

        let rows = CorrectionTally.top(
            [Self.entry("get hub", count: 3, last: 100)], limit: 5, rules: [disabled]
        )

        #expect(rows.map(\.hasRule) == [false])
    }
}
