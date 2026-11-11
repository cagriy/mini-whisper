import Testing

import MWMeetings
import MWOverlaySim
import MWTestCall

@Suite struct ScenarioLibraryTests {
    /// Capitalised words in vocative position: "Priya, can you…" at a sentence start, or
    /// "…, Priya?" at a sentence end.
    private func vocatives(in text: String) -> [String] {
        let opening = /(?:^|[.?!]\s+)(\p{Lu}[\w']*),/
        let closing = /,\s+(\p{Lu}[\w']*)[.?!]/
        return text.matches(of: opening).map { String($0.1) } + text.matches(of: closing).map { String($0.1) }
    }

    @Test func eightScenariosWithUniqueIDs() {
        let expected = [
            ("sprint-planning", "Sprint planning", "Daniel", "Karen"),
            ("budget-review", "Budget review", "Samantha", "Rishi"),
            ("incident-review", "Incident review", "Moira", "Daniel"),
            ("hiring-debrief", "Hiring debrief", "Karen", "Tessa"),
            ("product-launch", "Product launch", "Samantha", "Daniel"),
            ("customer-escalation", "Customer escalation", "Rishi", "Moira"),
            ("office-move", "Office move", "Tessa", "Karen"),
            ("quarterly-sales", "Quarterly sales", "Daniel", "Samantha"),
        ]
        let all = ScenarioLibrary.all

        #expect(all.map(\.id) == expected.map(\.0))
        #expect(all.map(\.title) == expected.map(\.1))
        #expect(all.map { $0.voices.map(\.requested) } == expected.map { [$0.2, $0.3] })
        #expect(Set(all.map(\.id)).count == all.count)
        for (id, title, _, _) in expected {
            #expect(ScenarioLibrary.scenario(id: id)?.title == title)
        }
        #expect(ScenarioLibrary.scenario(id: "no-such-scenario") == nil)
    }

    @Test func everyRevisionIsAtLeastOne() {
        for scenario in ScenarioLibrary.all {
            #expect(scenario.revision >= 1, "\(scenario.id)")
        }
    }

    @Test func twoDistinctVoiceRolesEach() {
        for scenario in ScenarioLibrary.all {
            #expect(scenario.voices.map(\.role) == [.a, .b], "\(scenario.id)")
            #expect(Set(scenario.voices.map(\.character)).count == 2, "\(scenario.id)")
            #expect(Set(scenario.voices.map(\.requested)).count == 2, "\(scenario.id)")
            #expect(Set(scenario.lines.map(\.role)) == [.you, .a, .b], "\(scenario.id)")
        }
    }

    @Test func tenToFourteenLinesWithFourOfTheUsers() {
        for scenario in ScenarioLibrary.all {
            #expect((10...14).contains(scenario.lines.count), "\(scenario.id)")
            #expect(scenario.lines.count { $0.role == .you } == 4, "\(scenario.id)")
        }
    }

    @Test func referenceTokensAreBetween120And200() {
        let normalizer = TranscriptNormalizer()
        for scenario in ScenarioLibrary.all {
            let tokens = scenario.lines.reduce(0) { $0 + normalizer.tokens($1.text).count }
            #expect((120...200).contains(tokens), "\(scenario.id): \(tokens)")
        }
    }

    @Test func noLineStartsWithADash() {
        for scenario in ScenarioLibrary.all {
            for (index, line) in scenario.lines.enumerated() {
                #expect(!line.text.hasPrefix("-"), "\(scenario.id) line \(index + 1)")
            }
        }
    }

    @Test func scriptsContainNoDigits() {
        for scenario in ScenarioLibrary.all {
            for (index, line) in scenario.lines.enumerated() {
                let digits = line.text.filter(\.isNumber)
                #expect(digits.isEmpty, "\(scenario.id) line \(index + 1)")
            }
        }
    }

    @Test func vocativesNameOnlyTheScenariosCharacters() {
        #expect(vocatives(in: "Alex, can you send it? Send it today, Priya.") == ["Alex", "Priya"])

        for scenario in ScenarioLibrary.all {
            let characters = Set(scenario.voices.map(\.character))
            for (index, line) in scenario.lines.enumerated() {
                for name in vocatives(in: line.text) {
                    #expect(characters.contains(name), "\(scenario.id) line \(index + 1): \(name)")
                }
            }
        }
    }

    @Test func pickRandomIsUniformAndReproducible() {
        var first = SeededRandom(seed: 42)
        var second = SeededRandom(seed: 42)
        let sequence = (0..<20).map { _ in ScenarioLibrary.pick(.random, using: &first).id }
        #expect(sequence == (0..<20).map { _ in ScenarioLibrary.pick(.random, using: &second).id })

        var rng = SeededRandom(seed: 7)
        var counts: [String: Int] = [:]
        for _ in 0..<8_000 {
            counts[ScenarioLibrary.pick(.random, using: &rng).id, default: 0] += 1
        }
        for scenario in ScenarioLibrary.all {
            #expect((850...1_150).contains(counts[scenario.id, default: 0]), "\(scenario.id)")
        }
    }

    @Test func pickNamedReturnsThatScenario() {
        var rng = SeededRandom(seed: 1)
        for scenario in ScenarioLibrary.all {
            #expect(ScenarioLibrary.pick(.named(scenario.id), using: &rng) == scenario)
        }
    }

    @Test func pickNamedWithAnUnknownIDFallsBackToRandom() {
        var named = SeededRandom(seed: 3)
        var random = SeededRandom(seed: 3)
        let picks = (0..<20).map { _ in ScenarioLibrary.pick(.named("no-such-scenario"), using: &named).id }

        #expect(picks == (0..<20).map { _ in ScenarioLibrary.pick(.random, using: &random).id })
        #expect(Set(picks).count > 1)
    }
}
