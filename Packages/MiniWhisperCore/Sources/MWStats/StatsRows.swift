import Foundation

// Rows leave out zero and empty fields, read a missing one as zero and ignore keys they do not
// know, so a row written by any build reads in any other. Optional fields are written whenever
// they are set, zero included.

/// One line of `dictations.jsonl`: one dictation attempt.
public struct DictationRow: Sendable, Equatable {
    /// The history entry's id when delivered.
    public var id: String
    /// `StatsTime.iso` of when the attempt was recorded.
    public var at: String
    /// Bundle identifier of the target app.
    public var app: String?
    /// `nil` for a batch-only dictation.
    public var engine: String?
    public var seconds: Double
    public var words: Int
    public var outcome: DictationAttempt.Outcome
    /// Key release to the paste returning; delivered live attempts only.
    public var wait: Double?
    public var usd: Double
    /// Taken from history when the record was seeded.
    public var seeded: Bool

    public init(
        id: String, at: String, app: String? = nil, engine: String? = nil, seconds: Double = 0,
        words: Int = 0, outcome: DictationAttempt.Outcome, wait: Double? = nil, usd: Double = 0,
        seeded: Bool = false
    ) {
        self.id = id
        self.at = at
        self.app = app
        self.engine = engine
        self.seconds = seconds
        self.words = words
        self.outcome = outcome
        self.wait = wait
        self.usd = usd
        self.seeded = seeded
    }
}

/// What one purpose cost on a day.
public struct Spend: Sendable, Equatable {
    public var usd: Double
    public var tokensIn: Int
    public var tokensOut: Int
    /// Engine seconds by pricing key.
    public var seconds: [String: Double]

    public init(usd: Double = 0, tokensIn: Int = 0, tokensOut: Int = 0, seconds: [String: Double] = [:]) {
        self.usd = usd
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.seconds = seconds
    }

    public mutating func add(_ other: Spend) {
        usd += other.usd
        tokensIn += other.tokensIn
        tokensOut += other.tokensOut
        seconds.merge(other.seconds, uniquingKeysWith: +)
    }
}

/// One line of `days.jsonl`. Lines hold one event's increments; a day is the sum of its lines.
public struct DayRow: Sendable, Equatable {
    /// Local `yyyy-MM-dd`.
    public var day: String
    public var delivered: Int
    public var words: Int
    /// Speaking seconds of delivered dictations that have a length.
    public var seconds: Double
    /// Words of those same dictations.
    public var timedWords: Int
    /// Attempts not delivered, by outcome.
    public var undelivered: [String: Int]
    /// Delivered count by bundle identifier, `other` when unknown.
    public var apps: [String: Int]
    /// Delivered count by local hour, `"0"`…`"23"`.
    public var hours: [String: Int]
    /// By purpose: `dictation`, `meeting`, `summary`, `naming` and `unsplit`.
    public var spend: [String: Spend]

    public init(
        day: String, delivered: Int = 0, words: Int = 0, seconds: Double = 0, timedWords: Int = 0,
        undelivered: [String: Int] = [:], apps: [String: Int] = [:], hours: [String: Int] = [:],
        spend: [String: Spend] = [:]
    ) {
        self.day = day
        self.delivered = delivered
        self.words = words
        self.seconds = seconds
        self.timedWords = timedWords
        self.undelivered = undelivered
        self.apps = apps
        self.hours = hours
        self.spend = spend
    }

    /// Field by field; `day` stays this row's.
    public mutating func add(_ other: DayRow) {
        delivered += other.delivered
        words += other.words
        seconds += other.seconds
        timedWords += other.timedWords
        undelivered.merge(other.undelivered, uniquingKeysWith: +)
        apps.merge(other.apps, uniquingKeysWith: +)
        hours.merge(other.hours, uniquingKeysWith: +)
        for (purpose, amount) in other.spend {
            spend[purpose, default: Spend()].add(amount)
        }
    }
}

/// One line of `meetings.jsonl`, the figures of one finished meeting; the latest line per `id`
/// wins.
public struct MeetingRow: Sendable, Equatable {
    public struct Speaker: Sendable, Equatable {
        public var id: Int
        public var seconds: Double
        public var words: Int
        public var questions: Int

        public init(id: Int, seconds: Double = 0, words: Int = 0, questions: Int = 0) {
            self.id = id
            self.seconds = seconds
            self.words = words
            self.questions = questions
        }
    }

    public struct Costs: Sendable, Equatable {
        public var meeting: Double
        /// Current plus replaced summaries.
        public var summary: Double
        public var naming: Double

        public init(meeting: Double = 0, summary: Double = 0, naming: Double = 0) {
            self.meeting = meeting
            self.summary = summary
            self.naming = naming
        }
    }

    /// Live transcript delay in seconds.
    public struct Delay: Sendable, Equatable {
        public var median: Double
        public var p90: Double
        public var count: Int

        public init(median: Double, p90: Double, count: Int) {
            self.median = median
            self.p90 = p90
            self.count = count
        }
    }

    public var id: UUID
    /// Start and end as `StatsTime.iso` at the meeting's own offset.
    public var at: String
    public var end: String
    /// Recorded seconds, pauses excluded.
    public var duration: Double
    public var mode: String
    public var engine: String
    /// Σ segment lengths.
    public var speech: Double
    public var words: Int
    /// Speaker id of the label marked as the user.
    public var user: Int?
    /// Remote, or the user has words: only then does talk share count the meeting.
    public var userKnown: Bool
    public var speakers: [Speaker]
    /// Non-user speakers with a real name.
    public var named: Int
    public var turns: Int
    public var longestTurn: Double
    public var questions: Int
    public var notes: Int
    public var gaps: Double
    public var paused: Double
    public var reconnects: Int
    public var silenceStop: Bool
    public var summary: Bool
    public var usd: Costs
    public var delay: Delay?
    public var summaryWait: Double?
    /// The figures version that computed the row.
    public var figures: Int
    /// UTC instant the row was computed.
    public var computed: String

    public init(
        id: UUID, at: String = "", end: String = "", duration: Double = 0, mode: String = "",
        engine: String = "", speech: Double = 0, words: Int = 0, user: Int? = nil,
        userKnown: Bool = false, speakers: [Speaker] = [], named: Int = 0, turns: Int = 0,
        longestTurn: Double = 0, questions: Int = 0, notes: Int = 0, gaps: Double = 0,
        paused: Double = 0, reconnects: Int = 0, silenceStop: Bool = false, summary: Bool = false,
        usd: Costs = Costs(), delay: Delay? = nil, summaryWait: Double? = nil, figures: Int = 0,
        computed: String = ""
    ) {
        self.id = id
        self.at = at
        self.end = end
        self.duration = duration
        self.mode = mode
        self.engine = engine
        self.speech = speech
        self.words = words
        self.user = user
        self.userKnown = userKnown
        self.speakers = speakers
        self.named = named
        self.turns = turns
        self.longestTurn = longestTurn
        self.questions = questions
        self.notes = notes
        self.gaps = gaps
        self.paused = paused
        self.reconnects = reconnects
        self.silenceStop = silenceStop
        self.summary = summary
        self.usd = usd
        self.delay = delay
        self.summaryWait = summaryWait
        self.figures = figures
        self.computed = computed
    }

    /// A meeting under a minute is kept but left out of every count and display.
    public var isCounted: Bool { duration >= 60 }

    /// The start's wall clock where the meeting took place, carrying that calendar and zone, so
    /// `date` gives the instant back. Nil when `at` is not in `StatsTime.iso`'s shape.
    public var localStart: DateComponents? { Self.local(at) }
    public var localEnd: DateComponents? { Self.local(end) }

    private static func local(_ text: String) -> DateComponents? {
        guard let parsed = StatsTime.parse(text), let zone = TimeZone(secondsFromGMT: parsed.offset) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.dateComponents(in: zone, from: parsed.date)
    }
}

/// `meta.json`. Its existence marks the record as seeded.
public struct StatsMeta: Codable, Sendable, Equatable {
    public var schema: Int
    /// Local `yyyy-MM-dd` the record started.
    public var since: String
    /// UTC instant.
    public var created: String

    public init(schema: Int = 1, since: String, created: String) {
        self.schema = schema
        self.since = since
        self.created = created
    }
}

/// The whole record at one moment: the rows as the store holds them.
public struct StatsSnapshot: Sendable, Equatable {
    /// In the order recorded.
    public var dictations: [DictationRow]
    /// One a day, oldest first.
    public var days: [DayRow]
    /// One per meeting.
    public var meetings: [MeetingRow]

    public init(dictations: [DictationRow] = [], days: [DayRow] = [], meetings: [MeetingRow] = []) {
        self.dictations = dictations
        self.days = days
        self.meetings = meetings
    }
}

// MARK: - Coding

private extension KeyedEncodingContainer {
    mutating func encode<Value: Encodable & Equatable>(_ value: Value, unless empty: Value, forKey key: Key) throws {
        if value != empty { try encode(value, forKey: key) }
    }
}

private extension KeyedDecodingContainer {
    func decode<Value: Decodable>(_ key: Key, or fallback: Value) throws -> Value {
        try decodeIfPresent(Value.self, forKey: key) ?? fallback
    }
}

extension DictationRow: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, at, app, engine, seconds, words, outcome, wait, usd, seeded
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        at = try container.decode(String.self, forKey: .at)
        app = try container.decodeIfPresent(String.self, forKey: .app)
        engine = try container.decodeIfPresent(String.self, forKey: .engine)
        seconds = try container.decode(.seconds, or: 0)
        words = try container.decode(.words, or: 0)
        outcome = try container.decode(DictationAttempt.Outcome.self, forKey: .outcome)
        wait = try container.decodeIfPresent(Double.self, forKey: .wait)
        usd = try container.decode(.usd, or: 0)
        seeded = try container.decode(.seeded, or: false)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(at, forKey: .at)
        try container.encodeIfPresent(app, forKey: .app)
        try container.encodeIfPresent(engine, forKey: .engine)
        try container.encode(seconds, unless: 0, forKey: .seconds)
        try container.encode(words, unless: 0, forKey: .words)
        try container.encode(outcome, forKey: .outcome)
        try container.encodeIfPresent(wait, forKey: .wait)
        try container.encode(usd, unless: 0, forKey: .usd)
        try container.encode(seeded, unless: false, forKey: .seeded)
    }
}

extension Spend: Codable {
    private enum CodingKeys: String, CodingKey {
        case usd
        case tokensIn = "tokens_in"
        case tokensOut = "tokens_out"
        case seconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usd = try container.decode(.usd, or: 0)
        tokensIn = try container.decode(.tokensIn, or: 0)
        tokensOut = try container.decode(.tokensOut, or: 0)
        seconds = try container.decode(.seconds, or: [:])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usd, unless: 0, forKey: .usd)
        try container.encode(tokensIn, unless: 0, forKey: .tokensIn)
        try container.encode(tokensOut, unless: 0, forKey: .tokensOut)
        try container.encode(seconds, unless: [:], forKey: .seconds)
    }
}

extension DayRow: Codable {
    private enum CodingKeys: String, CodingKey {
        case day, delivered, words, seconds
        case timedWords = "timed_words"
        case undelivered, apps, hours, spend
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        delivered = try container.decode(.delivered, or: 0)
        words = try container.decode(.words, or: 0)
        seconds = try container.decode(.seconds, or: 0)
        timedWords = try container.decode(.timedWords, or: 0)
        undelivered = try container.decode(.undelivered, or: [:])
        apps = try container.decode(.apps, or: [:])
        hours = try container.decode(.hours, or: [:])
        spend = try container.decode(.spend, or: [:])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try container.encode(delivered, unless: 0, forKey: .delivered)
        try container.encode(words, unless: 0, forKey: .words)
        try container.encode(seconds, unless: 0, forKey: .seconds)
        try container.encode(timedWords, unless: 0, forKey: .timedWords)
        try container.encode(undelivered, unless: [:], forKey: .undelivered)
        try container.encode(apps, unless: [:], forKey: .apps)
        try container.encode(hours, unless: [:], forKey: .hours)
        try container.encode(spend, unless: [:], forKey: .spend)
    }
}

extension MeetingRow.Speaker: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, seconds, words, questions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(.id, or: 0)
        seconds = try container.decode(.seconds, or: 0)
        words = try container.decode(.words, or: 0)
        questions = try container.decode(.questions, or: 0)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, unless: 0, forKey: .id)
        try container.encode(seconds, unless: 0, forKey: .seconds)
        try container.encode(words, unless: 0, forKey: .words)
        try container.encode(questions, unless: 0, forKey: .questions)
    }
}

extension MeetingRow.Costs: Codable {
    private enum CodingKeys: String, CodingKey {
        case meeting, summary, naming
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meeting = try container.decode(.meeting, or: 0)
        summary = try container.decode(.summary, or: 0)
        naming = try container.decode(.naming, or: 0)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(meeting, unless: 0, forKey: .meeting)
        try container.encode(summary, unless: 0, forKey: .summary)
        try container.encode(naming, unless: 0, forKey: .naming)
    }
}

extension MeetingRow.Delay: Codable {
    private enum CodingKeys: String, CodingKey {
        case median, p90, count
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        median = try container.decode(.median, or: 0)
        p90 = try container.decode(.p90, or: 0)
        count = try container.decode(.count, or: 0)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(median, unless: 0, forKey: .median)
        try container.encode(p90, unless: 0, forKey: .p90)
        try container.encode(count, unless: 0, forKey: .count)
    }
}

extension MeetingRow: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, at, end, duration, mode, engine, speech, words, user
        case userKnown = "user_known"
        case speakers, named, turns
        case longestTurn = "longest_turn"
        case questions, notes, gaps, paused, reconnects
        case silenceStop = "silence_stop"
        case summary, usd, delay
        case summaryWait = "summary_wait"
        case figures, computed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        at = try container.decode(.at, or: "")
        end = try container.decode(.end, or: "")
        duration = try container.decode(.duration, or: 0)
        mode = try container.decode(.mode, or: "")
        engine = try container.decode(.engine, or: "")
        speech = try container.decode(.speech, or: 0)
        words = try container.decode(.words, or: 0)
        user = try container.decodeIfPresent(Int.self, forKey: .user)
        userKnown = try container.decode(.userKnown, or: false)
        speakers = try container.decode(.speakers, or: [])
        named = try container.decode(.named, or: 0)
        turns = try container.decode(.turns, or: 0)
        longestTurn = try container.decode(.longestTurn, or: 0)
        questions = try container.decode(.questions, or: 0)
        notes = try container.decode(.notes, or: 0)
        gaps = try container.decode(.gaps, or: 0)
        paused = try container.decode(.paused, or: 0)
        reconnects = try container.decode(.reconnects, or: 0)
        silenceStop = try container.decode(.silenceStop, or: false)
        summary = try container.decode(.summary, or: false)
        usd = try container.decode(.usd, or: Costs())
        delay = try container.decodeIfPresent(Delay.self, forKey: .delay)
        summaryWait = try container.decodeIfPresent(Double.self, forKey: .summaryWait)
        figures = try container.decode(.figures, or: 0)
        computed = try container.decode(.computed, or: "")
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(at, unless: "", forKey: .at)
        try container.encode(end, unless: "", forKey: .end)
        try container.encode(duration, unless: 0, forKey: .duration)
        try container.encode(mode, unless: "", forKey: .mode)
        try container.encode(engine, unless: "", forKey: .engine)
        try container.encode(speech, unless: 0, forKey: .speech)
        try container.encode(words, unless: 0, forKey: .words)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encode(userKnown, unless: false, forKey: .userKnown)
        try container.encode(speakers, unless: [], forKey: .speakers)
        try container.encode(named, unless: 0, forKey: .named)
        try container.encode(turns, unless: 0, forKey: .turns)
        try container.encode(longestTurn, unless: 0, forKey: .longestTurn)
        try container.encode(questions, unless: 0, forKey: .questions)
        try container.encode(notes, unless: 0, forKey: .notes)
        try container.encode(gaps, unless: 0, forKey: .gaps)
        try container.encode(paused, unless: 0, forKey: .paused)
        try container.encode(reconnects, unless: 0, forKey: .reconnects)
        try container.encode(silenceStop, unless: false, forKey: .silenceStop)
        try container.encode(summary, unless: false, forKey: .summary)
        try container.encode(usd, unless: Costs(), forKey: .usd)
        try container.encodeIfPresent(delay, forKey: .delay)
        try container.encodeIfPresent(summaryWait, forKey: .summaryWait)
        try container.encode(figures, unless: 0, forKey: .figures)
        try container.encode(computed, unless: "", forKey: .computed)
    }
}
