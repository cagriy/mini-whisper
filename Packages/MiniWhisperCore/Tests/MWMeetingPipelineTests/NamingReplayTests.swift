import Foundation
import MWMeetings
import MWNaming
import MWSupport
import MWTestSupport
import MWTranscription
import Testing

@testable import MWMeetingPipeline

private let environment = ProcessInfo.processInfo.environment

private let liveKey: String? = {
    guard environment["MW_INTEGRATION"] == "1", let key = environment["ANTHROPIC_API_KEY"], !key.isEmpty
    else { return nil }
    return key
}()

private let replayDirectory: URL? = {
    guard let path = environment["MW_NAMING_REPLAY_DIR"], !path.isEmpty else { return nil }
    return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
}()

/// Opt-in: replays stored meetings through live naming and the Stop pass against Anthropic, about
/// $0.55 for the evaluation set. It reads the meetings, writes nothing and asserts nothing about
/// accuracy. Command, with `ANTHROPIC_API_KEY` exported:
/// `MW_INTEGRATION=1 MW_NAMING_REPLAY_DIR=<meetings folder> swift test --filter NamingReplayTests`.
@MainActor
@Suite(.enabled(if: liveKey != nil && replayDirectory != nil))
struct NamingReplayTests {
    @Test func replaysStoredMeetings() async throws {
        let client = AnthropicClient(apiKey: try #require(liveKey))
        // Typed as the reading protocol, so no store write is reachable.
        let store: any MeetingReading = MeetingStore(directory: try #require(replayDirectory))
        var score = Score()
        var spend = Spend()
        var meetings = 0
        for entry in try store.index() where entry.test == nil {
            let replay = MeetingReplay(try store.load(entry.id), client: client)
            // Nothing to score, so nothing worth paying for.
            guard !replay.truth.isEmpty else { continue }
            await replay.run()
            print(replay.report(into: &score))
            spend.add(replay.spend)
            meetings += 1
        }
        print("Totals over \(meetings) meetings: \(score.summary)\n  \(spend.summary)")
    }
}

/// One stored meeting as if live. Each request is awaited where the trigger fired, so it carries
/// the transcript the live meeting had then; no segment lands during a flight, so the follow-up
/// never fires.
@MainActor
private final class MeetingReplay {
    /// The names the user gave, hidden from the replay.
    let truth: [Int: String]
    private(set) var spend = Spend()
    private let meeting: Meeting
    private let segments: [Segment]
    private let keys: [Int: [String]]
    private let clock: VirtualClock
    private let route: MeetingNamingRoute
    private var registry: SpeakerRegistry
    private var heard: [Segment] = []
    private var firstHeard: [Int: Double] = [:]
    /// Each name a speaker was shown, when first shown.
    private var shown: [Int: [(name: String, at: Double)]] = [:]
    private var paused: String?

    init(_ loaded: LoadedMeeting, client: any NameSuggesting) {
        let speakers = loaded.meeting.speakers
        let spoke = Set(loaded.segments.map(\.speaker))
        let named = speakers.filter {
            !$0.isUser && spoke.contains($0.id) && $0.name != SpeakerLabel.defaultName($0.id)
        }
        truth = Dictionary(named.map { ($0.id, $0.name) }) { first, _ in first }
        keys = Dictionary(speakers.map { ($0.id, $0.providerKeys) }) { first, _ in first }
        registry = SpeakerRegistry(labels: speakers.filter(\.isUser))
        meeting = loaded.meeting
        // Segments arrive as they end.
        segments = loaded.segments.sorted { $0.end < $1.end }
        let clock = VirtualClock()
        self.clock = clock
        // People would give the hidden names away.
        route = MeetingNamingRoute(client: client, people: { [] }, clock: clock, overrides: [:])
    }

    func run() async {
        for segment in segments {
            clock.advance(by: segment.end - clock.now)
            // The 1 s ticker would have fired in the silence before this segment.
            if route.tick(at: segment.end) { await ask(.live) }
            hear(segment)
            if route.segmentsAdded([segment], speakers: registry.labels, known: [meeting.userName]) {
                await ask(.live)
            }
        }
        route.disarm()
        await ask(.stop)
    }

    func report(into score: inout Score) -> String {
        var lines = [
            "\(meeting.title) · \(meeting.startedAt.formatted(date: .numeric, time: .shortened)) · "
                + "\(timeText(meeting.durationSeconds)) · \(meeting.mode.rawValue)",
        ]
        for id in firstHeard.keys.sorted() where id != SpeakerRegistry.userID {
            let names = shown[id] ?? []
            let history = names.isEmpty ? "" : "; shown "
                + names.map { "\($0.name) \(timeText($0.at))" }.joined(separator: ", ")
            let speaker = "  \(SpeakerLabel.defaultName(id)) (\(truth[id] ?? "unnamed in the meeting")), "
                + "heard from \(timeText(firstHeard[id] ?? 0))"
            guard let name = truth[id] else {
                if !names.isEmpty { lines.append(speaker + history) }
                continue
            }
            let right = names.first { sameName($0.name, name) }?.at
            let wrong = names.count(where: { !sameName($0.name, name) })
            score.add(firstRight: right, wrongNames: wrong)
            let verdict = right.map { "right at \(timeText($0))" } ?? (wrong > 0 ? "wrong" : "missing")
            lines.append("\(speaker): \(verdict)\(history)")
        }
        lines.append("  \(spend.summary)" + (paused.map { ", paused: \($0)" } ?? ""))
        return lines.joined(separator: "\n")
    }

    private func hear(_ segment: Segment) {
        let id = segment.speaker
        if firstHeard[id] == nil {
            firstHeard[id] = segment.start
            if !registry.labels.contains(where: { $0.id == id }) {
                // Joins as live speakers do, under the default name, with its stored provider keys.
                let label = SpeakerLabel(id: id, name: SpeakerLabel.defaultName(id), providerKeys: keys[id] ?? [])
                registry = SpeakerRegistry(labels: registry.labels + [label])
            }
        }
        heard.append(segment)
    }

    /// The controller's checks before a request; naming is on and the key present by construction.
    private func ask(_ scope: NamingScope) async {
        guard !route.isPaused, registry.labels.contains(where: SuggestionPolicy.isOpen) else { return }
        let snapshot = NamingSnapshot(
            scope: scope, segments: heard, speakers: registry.labels, userName: meeting.userName,
            mode: meeting.mode, aliases: []
        )
        let outcome = await route.run(snapshot: snapshot) { self.context }
        // Auto-apply is off, as shipped, so every action is a suggestion.
        for case .suggest(let speaker, let match) in outcome.actions {
            registry.suggestFromConversation(match, speaker: speaker)
        }
        for label in registry.labels {
            for match in label.matches where match.source == "conversation"
                && !(shown[label.id] ?? []).contains(where: { $0.name == match.name }) {
                shown[label.id, default: []].append((match.name, clock.now))
            }
        }
        spend.add(Spend(
            requests: 1, failures: outcome.failure == nil ? 0 : 1, cost: outcome.cost,
            usage: outcome.usage ?? TokenUsage()
        ))
        if let pause = outcome.pause { paused = pause.reason }
    }

    private var context: PolicyContext {
        PolicyContext(
            speakers: registry.labels, people: [], userName: meeting.userName, aliases: [], mode: meeting.mode,
            autoApply: false, segmentSpeakers: Dictionary(heard.map { ($0.id, $0.speaker) }) { $1 }
        )
    }
}

/// A speaker is right once shown the right name, wrong when shown only others, missing when shown none.
private struct Score {
    private var speakers = 0
    private var wrong = 0
    private var missing = 0
    /// Wrong-person names shown, on any named speaker, right ones included.
    private var wrongNames = 0
    private var firstRight: [Double] = []

    mutating func add(firstRight right: Double?, wrongNames: Int) {
        speakers += 1
        self.wrongNames += wrongNames
        if let right {
            firstRight.append(right)
        } else if wrongNames > 0 {
            wrong += 1
        } else {
            missing += 1
        }
    }

    var summary: String {
        let right = firstRight.count
        let sorted = firstRight.sorted()
        let median = sorted.isEmpty ? "none" : timeText((sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2)
        return "\(speakers) named speakers: \(right) right, \(wrong) wrong, \(missing) missing; "
            + "\(wrongNames) wrong-person names shown; median first right name at \(median)"
    }
}

private struct Spend {
    var requests = 0
    var failures = 0
    var cost = 0.0
    var usage = TokenUsage()

    mutating func add(_ other: Spend) {
        requests += other.requests
        failures += other.failures
        cost += other.cost
        usage.inputTokens += other.usage.inputTokens
        usage.cacheReadTokens += other.usage.cacheReadTokens
        usage.cacheWriteTokens += other.usage.cacheWriteTokens
        usage.outputTokens += other.usage.outputTokens
    }

    var summary: String {
        "\(requests) requests, \(failures) failed, \(usage.inputTokens) input / \(usage.cacheReadTokens) cache-read / "
            + "\(usage.cacheWriteTokens) cache-write / \(usage.outputTokens) output tokens, "
            + "$\(String(format: "%.4f", cost))"
    }
}

/// A first name for a full name, or the reverse, is the same person: a conversation rarely says both.
private func sameName(_ shown: String, _ truth: String) -> Bool {
    let shown = NameFold.key(shown).split(separator: " ")
    let truth = NameFold.key(truth).split(separator: " ")
    return shown.starts(with: truth) || truth.starts(with: shown)
}

private func timeText(_ seconds: Double) -> String {
    String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
}
