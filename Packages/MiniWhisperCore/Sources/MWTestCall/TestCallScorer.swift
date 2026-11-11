import Foundation
import MWConfig
import MWMeetings

/// Scores a test call from the engine's segments as they stand after the session drains (design
/// §5.5): transcript words go to script lines by time, each `done` line is aligned against its
/// words, and the lines sum to WER, speaker labels and latency per role and overall.
public struct TestCallScorer: Sendable {
    private let normalizer = TranscriptNormalizer()
    private let aligner = WordAligner()

    public init() {}

    /// The span whose transcript words may belong to a line: engines time words a little early and
    /// finalise a line's last words after it ends.
    public static func window(start: Double, end: Double) -> ClosedRange<Double> {
        (start - 0.5)...(end + 1.5)
    }

    /// Purity of at least 95%, and no other role has the same majority label (R16).
    public static func isClean(_ role: TestCallRecord.RoleScore, among roles: [TestCallRecord.RoleScore]) -> Bool {
        guard let label = role.majorityLabel, let purity = role.purity, purity >= 0.95 else { return false }
        return !roles.contains { $0.role != role.role && $0.majorityLabel == label }
    }

    /// `arrivals` holds each segment's arrival in meeting seconds, `speakers` the meeting's labels
    /// and `userSpeaker` the user's label id.
    public func score(
        run: TestCallRun,
        scenario: TestScenario,
        segments: [Segment],
        arrivals: [UUID: Double],
        speakers: [SpeakerLabel],
        userSpeaker: Int,
        engine: MeetingEngine,
        scoredAt: Date
    ) -> TestCallRecord {
        var scored = run.lines.filter { $0.status == .done }.map {
            ScoredLine(run: $0, reference: normalizer.sourced(scenario.lines[$0.index - 1].text))
        }
        assign(transcriptTokens(segments), to: &scored)

        var results: [Int: LineResult] = [:]
        var roleLabels: [TestCallRole: [Int: Int]] = [:]
        for line in scored {
            let result = result(of: line, arrivals: arrivals)
            results[line.run.index] = result
            roleLabels[line.run.role, default: [:]].merge(result.labels, uniquingKeysWith: +)
        }

        let lines = run.lines.map { line in
            let result = results[line.index]
            return TestCallRecord.Line(
                index: line.index, role: line.role, status: line.status, start: line.start, end: line.end,
                overlapped: line.overlapped, reference: scenario.lines[line.index - 1].text,
                counts: result?.counts, heard: result?.heard,
                labels: result.map { Dictionary(uniqueKeysWithValues: $0.labels.map { (String($0.key), $0.value) }) },
                segmentStart: result?.segmentStart, latency: result?.latency
            )
        }
        let roles = TestCallRole.allCases.map { role in
            roleScore(role, lines: lines.filter { $0.role == role }, labels: roleLabels[role] ?? [:], speakers: speakers)
        }
        let voiceLabels = (roleLabels[.a] ?? [:]).merging(roleLabels[.b] ?? [:], uniquingKeysWith: +)

        return TestCallRecord(
            scenario: .init(id: scenario.id, revision: scenario.revision, title: scenario.title),
            engine: engine,
            overlap: run.overlap,
            scoredAt: scoredAt,
            voices: TestCallRole.allCases.compactMap { run.casting[$0] }.map {
                .init(role: $0.role, character: $0.character, requested: $0.requested, voice: $0.voice)
            },
            lines: lines,
            roles: roles,
            overall: sum(roles.map(\.counts)),
            crossCredited: .init(
                voiceWordsAsYou: voiceLabels[userSpeaker] ?? 0,
                yourWordsAsVoices: (roleLabels[.you] ?? [:]).filter { $0.key != userSpeaker }.values.reduce(0, +)
            ),
            latency: latency(of: lines)
        )
    }

    // MARK: - Transcript tokens

    /// A comparable token of one transcript word, placed at the word's midpoint.
    private struct TranscriptToken {
        var token: String
        var time: Double
        /// Numbers the transcript's words across segments, grouping a word's tokens.
        var word: Int
        /// The word in the engine's spelling.
        var text: String
        var segment: UUID
        var segmentStart: Double
        var speaker: Int
    }

    /// In meeting time. A segment without word timings spreads its tokens evenly over its span.
    private func transcriptTokens(_ segments: [Segment]) -> [TranscriptToken] {
        var tokens: [TranscriptToken] = []
        var words = 0
        func add(_ sourced: [SourcedToken], of segment: Segment, at time: (Int) -> Double) {
            for (offset, token) in sourced.enumerated() {
                tokens.append(TranscriptToken(
                    token: token.token, time: time(offset), word: words + token.wordIndex, text: token.word,
                    segment: segment.id, segmentStart: segment.start, speaker: segment.speaker
                ))
            }
            words += sourced.last.map { $0.wordIndex + 1 } ?? 0
        }
        for segment in segments {
            if segment.words.isEmpty {
                let sourced = normalizer.sourced(segment.text)
                let step = (segment.end - segment.start) / Double(max(sourced.count, 1))
                add(sourced, of: segment) { segment.start + (Double($0) + 0.5) * step }
            } else {
                for word in segment.words {
                    add(normalizer.sourced(word.text), of: segment) { _ in (word.start + word.end) / 2 }
                }
            }
        }
        return tokens.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
    }

    // MARK: - Assignment

    private struct ScoredLine {
        var run: RunLine
        var reference: [SourcedToken]
        /// Reference tokens no assigned token has used yet, by token.
        var unconsumed: [String: Int]
        /// Nil only for a `done` line without times, which the conductor never records.
        var span: (start: Double, end: Double)?
        var tokens: [TranscriptToken] = []

        init(run: RunLine, reference: [SourcedToken]) {
            self.run = run
            self.reference = reference
            unconsumed = reference.reduce(into: [:]) { $0[$1.token, default: 0] += 1 }
            if let start = run.start, let end = run.end { span = (start, end) }
        }

        func windowContains(_ time: Double) -> Bool {
            span.map { TestCallScorer.window(start: $0.start, end: $0.end).contains(time) } ?? false
        }

        /// To the unpadded span; zero inside it.
        func distance(to time: Double) -> Double {
            span.map { max($0.start - time, time - $0.end, 0) } ?? .infinity
        }
    }

    /// A token in several windows goes to the earliest line still holding an equal unused token,
    /// failing that to the line whose unpadded span is nearest. A token in no window is dropped.
    private func assign(_ tokens: [TranscriptToken], to lines: inout [ScoredLine]) {
        for token in tokens {
            let candidates = lines.indices.filter { lines[$0].windowContains(token.time) }
            guard let nearest = candidates.min(by: { lines[$0].distance(to: token.time) < lines[$1].distance(to: token.time) })
            else { continue }
            let target = candidates.count == 1
                ? nearest
                : candidates.first { lines[$0].unconsumed[token.token, default: 0] > 0 } ?? nearest
            lines[target].tokens.append(token)
            if let left = lines[target].unconsumed[token.token], left > 0 {
                lines[target].unconsumed[token.token] = left - 1
            }
        }
    }

    // MARK: - Per line

    private struct LineResult {
        var counts: TestCallRecord.Counts
        var heard: [TestCallRecord.Heard]
        /// Tokens aligned to a script word, by speaker id.
        var labels: [Int: Int]
        var segmentStart: Double?
        var latency: Double?
    }

    private func result(of line: ScoredLine, arrivals: [UUID: Double]) -> LineResult {
        let tokens = line.tokens
        let alignment = aligner.align(reference: line.reference.map(\.token), hypothesis: tokens.map(\.token))

        // An inserted word is no word of the role, so only tokens standing for a script word carry a
        // label: purity and cross-credit count the role's own words.
        var labels: [Int: Int] = [:]
        var lastMatch: TranscriptToken?
        for op in alignment.ops {
            switch op {
            case let .match(_, hypothesis):
                labels[tokens[hypothesis].speaker, default: 0] += 1
                lastMatch = tokens[hypothesis]
            case let .substitute(_, hypothesis):
                labels[tokens[hypothesis].speaker, default: 0] += 1
            case .delete, .insert:
                break
            }
        }
        var latency: Double?
        if let lastMatch, let end = line.span?.end, let arrival = arrivals[lastMatch.segment] {
            latency = arrival - end
        }

        return LineResult(
            counts: .init(
                words: line.reference.count, substitutions: alignment.substitutions,
                deletions: alignment.deletions, insertions: alignment.insertions
            ),
            heard: heard(alignment, reference: line.reference, tokens: tokens),
            labels: labels,
            segmentStart: tokens.first?.segmentStart,
            latency: latency
        )
    }

    /// Transcript words in time order with their outcome, and missed script words where the
    /// alignment drops them. A run of consecutive error words is one entry naming the script words
    /// it replaced.
    private func heard(
        _ alignment: WordAligner.Alignment, reference: [SourcedToken], tokens: [TranscriptToken]
    ) -> [TestCallRecord.Heard] {
        enum Item {
            /// A transcript word, by its first token.
            case word(TranscriptToken)
            /// A script word, by its first deleted token.
            case missed(SourcedToken)
        }
        var items: [Item] = []
        var seen: Set<Int> = []
        var wrong: Set<Int> = []
        var replaced: [Int: [SourcedToken]] = [:]
        for op in alignment.ops {
            let token: TranscriptToken
            switch op {
            case let .match(_, hypothesis):
                token = tokens[hypothesis]
            case let .substitute(script, hypothesis):
                token = tokens[hypothesis]
                wrong.insert(token.word)
                replaced[token.word, default: []].append(reference[script])
            case let .insert(hypothesis):
                token = tokens[hypothesis]
                wrong.insert(token.word)
            case let .delete(script):
                if case let .missed(previous) = items.last, previous.wordIndex == reference[script].wordIndex { continue }
                items.append(.missed(reference[script]))
                continue
            }
            if seen.insert(token.word).inserted { items.append(.word(token)) }
        }

        var heard: [TestCallRecord.Heard] = []
        var script: [SourcedToken] = []
        for item in items {
            switch item {
            case let .missed(word):
                heard.append(.init(op: .missed, script: word.word))
            case let .word(token) where !wrong.contains(token.word):
                heard.append(.init(text: token.text, op: .match))
            case let .word(token):
                if let last = heard.last, last.op == .error, let text = last.text {
                    heard[heard.count - 1].text = text + " " + token.text
                } else {
                    heard.append(.init(text: token.text, op: .error))
                    script = []
                }
                for word in replaced[token.word] ?? [] where script.last?.wordIndex != word.wordIndex {
                    script.append(word)
                }
                heard[heard.count - 1].script = script.map(\.word).joined(separator: " ")
            }
        }
        return heard
    }

    // MARK: - Totals

    private func sum(_ counts: [TestCallRecord.Counts]) -> TestCallRecord.Counts {
        counts.reduce(.init(words: 0, substitutions: 0, deletions: 0, insertions: 0)) {
            .init(
                words: $0.words + $1.words, substitutions: $0.substitutions + $1.substitutions,
                deletions: $0.deletions + $1.deletions, insertions: $0.insertions + $1.insertions
            )
        }
    }

    private func roleScore(
        _ role: TestCallRole, lines: [TestCallRecord.Line], labels: [Int: Int], speakers: [SpeakerLabel]
    ) -> TestCallRecord.RoleScore {
        let counts = sum(lines.compactMap(\.counts))
        // The most words; a tie goes to the lower speaker id.
        let majority = labels.max { ($0.value, $1.key) < ($1.value, $0.key) }
        let total = labels.values.reduce(0, +)
        return .init(
            role: role, words: counts.words, substitutions: counts.substitutions, deletions: counts.deletions,
            insertions: counts.insertions, majorityLabel: majority?.key,
            majorityLabelName: majority.flatMap { majority in speakers.first { $0.id == majority.key }?.name },
            purity: majority.map { Double($0.value) / Double(total) }
        )
    }

    /// Median and max over the lines with a latency; the max's line is the earliest on a tie.
    private func latency(of lines: [TestCallRecord.Line]) -> TestCallRecord.Latency? {
        let timed = lines.compactMap { line in line.latency.map { (line: line.index, latency: $0) } }
        guard let max = timed.max(by: { $0.latency < $1.latency }) else { return nil }
        let sorted = timed.map(\.latency).sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return .init(median: median, max: max.latency, maxLine: max.line)
    }
}
