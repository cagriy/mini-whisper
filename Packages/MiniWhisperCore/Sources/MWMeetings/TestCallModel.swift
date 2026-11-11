import Foundation
import MWConfig

/// Marks a meeting as a test call (design §5.2). `wer` caches the overall score for the
/// Meetings list and the scenario menu; nil until scored.
public struct TestCallTag: Codable, Sendable, Equatable {
    public var scenarioID: String
    public var revision: Int
    public var scenarioTitle: String
    public var wer: Double?

    public init(scenarioID: String, revision: Int, scenarioTitle: String, wer: Double? = nil) {
        self.scenarioID = scenarioID
        self.revision = revision
        self.scenarioTitle = scenarioTitle
        self.wer = wer
    }
}

/// Who speaks a script line: the user or one of the two synthetic voices.
public enum TestCallRole: String, Codable, Sendable, CaseIterable {
    case you
    case a
    case b
}

/// Only `done` lines are scored.
public enum TestCallLineStatus: String, Codable, Sendable {
    case done
    case skipped
    case stopped
    case notReached
}

/// `testcall.json`, schema 1: the score of one test call, written once at Stop. It holds the
/// script text so it stays readable after the scenario's revision changes. Rates are never
/// stored; they derive from the counts.
public struct TestCallRecord: Codable, Sendable, Equatable {
    public static let currentSchema = 1

    public struct Scenario: Codable, Sendable, Equatable {
        public var id: String
        public var revision: Int
        public var title: String

        public init(id: String, revision: Int, title: String) {
            self.id = id
            self.revision = revision
            self.title = title
        }
    }

    public struct Voice: Codable, Sendable, Equatable {
        public var role: TestCallRole
        public var character: String
        /// The scenario's voice; `voice` differs when it had to be substituted.
        public var requested: String
        public var voice: String

        public init(role: TestCallRole, character: String, requested: String, voice: String) {
            self.role = role
            self.character = character
            self.requested = requested
            self.voice = voice
        }
    }

    public struct Counts: Codable, Sendable, Equatable {
        /// Reference words.
        public var words: Int
        public var substitutions: Int
        public var deletions: Int
        public var insertions: Int

        public init(words: Int, substitutions: Int, deletions: Int, insertions: Int) {
            self.words = words
            self.substitutions = substitutions
            self.deletions = deletions
            self.insertions = insertions
        }

        /// Nil without reference words.
        public var wer: Double? {
            words == 0 ? nil : Double(substitutions + deletions + insertions) / Double(words)
        }
    }

    /// One transcript word of a line in the engine's spelling, or a missed script word.
    public struct Heard: Codable, Sendable, Equatable {
        public enum Op: String, Codable, Sendable {
            case match
            case error
            case missed
        }

        /// Nil for `missed`.
        public var text: String?
        public var op: Op
        /// The script words an `error` replaced (empty for a pure insertion), or the `missed` word.
        public var script: String?

        public init(text: String? = nil, op: Op, script: String? = nil) {
            self.text = text
            self.op = op
            self.script = script
        }
    }

    /// Lines other than `done` carry no counts.
    public struct Line: Codable, Sendable, Equatable {
        public var index: Int
        public var role: TestCallRole
        public var status: TestCallLineStatus
        /// Meeting seconds.
        public var start: Double?
        public var end: Double?
        public var overlapped: Bool?
        public var reference: String
        public var counts: Counts?
        public var heard: [Heard]?
        /// Words per engine speaker id. String keys: `JSONEncoder` writes `[Int: Int]` as a flat array.
        public var labels: [String: Int]?
        public var segmentStart: Double?
        /// Seconds from the line's end to the arrival of its last matched word.
        public var latency: Double?

        public init(
            index: Int,
            role: TestCallRole,
            status: TestCallLineStatus,
            start: Double? = nil,
            end: Double? = nil,
            overlapped: Bool? = nil,
            reference: String,
            counts: Counts? = nil,
            heard: [Heard]? = nil,
            labels: [String: Int]? = nil,
            segmentStart: Double? = nil,
            latency: Double? = nil
        ) {
            self.index = index
            self.role = role
            self.status = status
            self.start = start
            self.end = end
            self.overlapped = overlapped
            self.reference = reference
            self.counts = counts
            self.heard = heard
            self.labels = labels
            self.segmentStart = segmentStart
            self.latency = latency
        }
    }

    public struct RoleScore: Codable, Sendable, Equatable {
        public var role: TestCallRole
        public var words: Int
        public var substitutions: Int
        public var deletions: Int
        public var insertions: Int
        public var majorityLabel: Int?
        /// The label's name at scoring; later renames leave it.
        public var majorityLabelName: String?
        /// The majority label's share of the role's words.
        public var purity: Double?

        public init(
            role: TestCallRole,
            words: Int,
            substitutions: Int,
            deletions: Int,
            insertions: Int,
            majorityLabel: Int? = nil,
            majorityLabelName: String? = nil,
            purity: Double? = nil
        ) {
            self.role = role
            self.words = words
            self.substitutions = substitutions
            self.deletions = deletions
            self.insertions = insertions
            self.majorityLabel = majorityLabel
            self.majorityLabelName = majorityLabelName
            self.purity = purity
        }

        public var counts: Counts {
            Counts(words: words, substitutions: substitutions, deletions: deletions, insertions: insertions)
        }
    }

    public struct CrossCredited: Codable, Sendable, Equatable {
        public var voiceWordsAsYou: Int
        public var yourWordsAsVoices: Int

        public init(voiceWordsAsYou: Int, yourWordsAsVoices: Int) {
            self.voiceWordsAsYou = voiceWordsAsYou
            self.yourWordsAsVoices = yourWordsAsVoices
        }
    }

    public struct Latency: Codable, Sendable, Equatable {
        public var median: Double
        public var max: Double
        /// The script line index of `max`.
        public var maxLine: Int

        public init(median: Double, max: Double, maxLine: Int) {
            self.median = median
            self.max = max
            self.maxLine = maxLine
        }
    }

    public var schema: Int
    public var scenario: Scenario
    public var engine: MeetingEngine
    public var overlap: Bool
    public var scoredAt: Date
    public var voices: [Voice]
    public var lines: [Line]
    public var roles: [RoleScore]
    public var overall: Counts
    public var crossCredited: CrossCredited
    /// Nil when no line has a latency.
    public var latency: Latency?

    public init(
        scenario: Scenario,
        engine: MeetingEngine,
        overlap: Bool,
        scoredAt: Date,
        voices: [Voice],
        lines: [Line],
        roles: [RoleScore],
        overall: Counts,
        crossCredited: CrossCredited,
        latency: Latency?
    ) {
        schema = Self.currentSchema
        self.scenario = scenario
        self.engine = engine
        self.overlap = overlap
        self.scoredAt = scoredAt
        self.voices = voices
        self.lines = lines
        self.roles = roles
        self.overall = overall
        self.crossCredited = crossCredited
        self.latency = latency
    }
}
