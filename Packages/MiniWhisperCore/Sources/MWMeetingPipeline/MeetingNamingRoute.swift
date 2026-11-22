import Foundation
import MWMeetings
import MWNaming
import MWSupport
import MWTranscription
import MWUsage

enum NamingScope: String, Sendable {
    case live, stop, manual
}

/// The meeting as it stood when a request was decided on; rendered off the main actor.
struct NamingSnapshot: Sendable {
    var scope: NamingScope
    var segments: [Segment]
    var speakers: [SpeakerLabel]
    var userName: String?
    var mode: MeetingMode
    var aliases: [String]
}

struct NamingOutcome: Sendable {
    var actions: [NamingAction] = []
    /// Nil when the request spent nothing.
    var usage: TokenUsage?
    var cost: Double = 0
    var failure: NamingError?
    /// A fire arrived during the flight: ask once more.
    var followUp = false
    /// Set by the run that paused naming.
    var pause: NamingError?
}

/// One meeting's naming: when to ask (trigger, single flight, one coalesced follow-up), what
/// to send, and the failures that pause it (R5, R6, R27). The policy decides what a reply means
/// and the controller alone changes the registry.
@MainActor
final class MeetingNamingRoute {
    private static let pauseAfter = 3

    private let client: any NameSuggesting
    private let readPeople: @Sendable () async -> [(id: UUID, name: String)]
    private let clock: any Clock
    private let overrides: [String: Double]
    private var trigger: NamingTrigger
    /// As last read: spotted as known names, offered in the request, and the policy's People.
    private var people: [(id: UUID, name: String)] = []
    private var failures = 0
    private var pausedBy: NamingError?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    /// `people` reads the People store without the user, who is passed separately.
    init(
        client: any NameSuggesting,
        people: @escaping @Sendable () async -> [(id: UUID, name: String)],
        clock: any Clock,
        overrides: [String: Double],
        delay: Double = NamingTrigger.defaultDelay
    ) {
        self.client = client
        readPeople = people
        self.clock = clock
        self.overrides = overrides
        trigger = NamingTrigger(delay: delay)
    }

    var isPaused: Bool { pausedBy != nil }
    var inFlight: Bool { trigger.inFlight }

    func reloadPeople() async {
        people = await readPeople()
    }

    /// True means start a request. Known names are People, `extra` and standing suggestions;
    /// times are each segment's end.
    func segmentsAdded(_ segments: [Segment], speakers: [SpeakerLabel], known extra: [String]) -> Bool {
        let suggested = speakers.flatMap { $0.matches.filter { $0.state == .suggested }.map(\.name) }
        let known = people.map(\.name) + extra + suggested
        var fires = false
        for segment in segments {
            let hasName = NameSpotter.containsName(segment.text, known: known)
            fires = trigger.segment(speaker: segment.speaker, hasName: hasName, at: segment.end) || fires
        }
        return fires
    }

    func tick(at time: Double) -> Bool {
        trigger.tick(at: time)
    }

    /// Sends one request and decides its reply against `context()`, read once the reply is in;
    /// nil drops the reply, though its tokens are still billed (R4). The context's `people` is
    /// replaced by the People this request offered, so the reply is decided against the
    /// spellings the model saw. A paused route runs only the manual scope.
    func run(snapshot: NamingSnapshot, context: @MainActor () async -> PolicyContext?) async -> NamingOutcome {
        let scope = snapshot.scope.rawValue
        guard snapshot.scope == .manual || !isPaused else { return NamingOutcome() }
        trigger.begin()
        await reloadPeople()
        let people = people
        let started = clock.now
        var outcome = NamingOutcome()
        do {
            let (rendered, reply) = try await Self.ask(client, snapshot: snapshot, people: people.map(\.name))
            failures = 0
            outcome.usage = reply.usage
            outcome.cost = Pricing.namingCost(reply.usage, overrides: overrides)
            Log.naming.info("\(scope) reply in \(seconds(since: started)) s: \(Self.figures(reply.usage, outcome.cost))")
            if var current = await context() {
                current.people = people
                let decision = SuggestionPolicy.decide(reply.suggestions, rendered: rendered, context: current)
                outcome.actions = decision.actions
                Log.naming.info("\(scope) policy: \(Self.counts(decision))")
            } else {
                Log.naming.info("\(scope) reply dropped: naming off or meeting closed")
            }
        } catch {
            let (failure, usage) = Self.failure(error)
            outcome.failure = failure
            if let usage {
                outcome.usage = usage
                outcome.cost = Pricing.namingCost(usage, overrides: overrides)
            }
            failures += 1
            let spent = usage.map { ", \(Self.figures($0, outcome.cost))" } ?? ""
            Log.naming.info("\(scope) failed after \(seconds(since: started)) s: \(Self.category(failure))\(spent)")
            if !isPaused, failure == .unauthorized || failures >= Self.pauseAfter {
                pausedBy = failure
                outcome.pause = failure
                trigger.disarm()
                Log.naming.info("paused: \(Self.category(failure)), \(failures) in a row")
            }
        }
        outcome.followUp = trigger.end()
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
        return outcome
    }

    /// Resolves once no request is in flight.
    func waitIdle() async {
        guard inFlight else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    /// Drops an armed trigger and a pending follow-up.
    func disarm() {
        trigger.disarm()
    }

    /// Rendering and decoding a long meeting stay off the main actor; the snapshot is a value.
    @concurrent
    private nonisolated static func ask(
        _ client: any NameSuggesting, snapshot: NamingSnapshot, people: [String]
    ) async throws -> (Rendered, NamingReply) {
        let rendered = NamingTranscript.render(segments: snapshot.segments)
        let state = NamingState(
            speakers: snapshot.speakers.map(SpeakerState.init), people: people, userName: snapshot.userName,
            aliases: snapshot.aliases, mode: snapshot.mode
        )
        let request = NamingPrompt.request(rendered, state: state)
        let characters = request.blocks.reduce(0) { $0 + $1.count }
        Log.naming.info("\(snapshot.scope.rawValue) request: \(rendered.turns.count) turns, \(characters) characters")
        return (rendered, try await client.suggestNames(request))
    }

    private func seconds(since start: TimeInterval) -> String {
        String(format: "%.1f", clock.now - start)
    }

    /// Any other error, such as a missing key read at call time, is a transport failure.
    private static func failure(_ error: any Error) -> (NamingError, TokenUsage?) {
        switch error {
        case let failure as NamingFailure: (failure.error, failure.usage)
        case let error as NamingError: (error, nil)
        default: (.transport(AnyError(error).description), nil)
        }
    }

    private static func figures(_ usage: TokenUsage, _ cost: Double) -> String {
        """
        \(usage.inputTokens) input / \(usage.cacheReadTokens) cache-read / \(usage.cacheWriteTokens) cache-write / \
        \(usage.outputTokens) output tokens, $\(String(format: "%.6f", cost))
        """
    }

    private static func counts(_ decision: NamingDecision) -> String {
        let applied = decision.actions.filter { if case .apply = $0 { true } else { false } }.count
        let dropped = decision.dropped.sorted { $0.key < $1.key }.map { "rule \($0.key): \($0.value)" }
        return "\(decision.actions.count - applied) suggested, \(applied) applied, dropped "
            + (dropped.isEmpty ? "none" : dropped.joined(separator: ", "))
    }

    /// Log-safe: a transport reason may carry system text.
    private static func category(_ error: NamingError) -> String {
        switch error {
        case .unauthorized: "unauthorized"
        case .rateLimited: "rate-limited"
        case .server(let status): "HTTP \(status)"
        case .refused: "refused"
        case .truncated: "truncated"
        case .malformed: "malformed"
        case .transport: "transport"
        }
    }
}
