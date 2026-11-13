import Foundation
import MWConfig

public enum MeetingMode: String, Codable, Sendable, Equatable {
    case remote
    case inRoom = "in-room"
}

/// One recognised word; times are meeting seconds.
public struct Word: Codable, Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey {
        case text = "t"
        case start = "s"
        case end = "e"
    }
}

/// One line of `segments.jsonl`.
public struct Segment: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// `SpeakerLabel.id`.
    public var speaker: Int
    /// Meeting seconds.
    public var start: Double
    public var end: Double
    public var text: String
    public var words: [Word]
    public var session: Int
    public var providerLabel: String?
    public var turnOrder: Int?
    public var edited: Bool
    /// Manually reassigned; a speaker revision never changes it.
    public var pinned: Bool

    public init(
        id: UUID = UUID(),
        speaker: Int,
        start: Double,
        end: Double,
        text: String,
        words: [Word] = [],
        session: Int,
        providerLabel: String? = nil,
        turnOrder: Int? = nil,
        edited: Bool = false,
        pinned: Bool = false
    ) {
        self.id = id
        self.speaker = speaker
        self.start = start
        self.end = end
        self.text = text
        self.words = words
        self.session = session
        self.providerLabel = providerLabel
        self.turnOrder = turnOrder
        self.edited = edited
        self.pinned = pinned
    }
}

/// One line of `notes.jsonl`.
public struct Note: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Meeting seconds of the first keystroke.
    public var time: Double
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), time: Double, text: String, createdAt: Date) {
        self.id = id
        self.time = time
        self.text = text
        self.createdAt = createdAt
    }
}

public struct Marker: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case gap
        case paused
        /// A pause the Mac's sleep caused.
        case sleep
    }

    public var kind: Kind
    /// Meeting seconds.
    public var start: Double
    public var end: Double
    public var reason: String?

    public init(kind: Kind, start: Double, end: Double, reason: String? = nil) {
        self.kind = kind
        self.start = start
        self.end = end
        self.reason = reason
    }
}

public struct Summary: Codable, Sendable, Equatable {
    /// The model's Markdown, read through `SummaryDocument`: a `##` section per topic, or the
    /// four fixed sections of older summaries.
    public var text: String
    public var model: String
    public var createdAt: Date
    public var inputTokens: Int
    public var outputTokens: Int
    public var costUSD: Double

    public init(text: String, model: String, createdAt: Date, inputTokens: Int, outputTokens: Int, costUSD: Double) {
        self.text = text
        self.model = model
        self.createdAt = createdAt
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
    }
}

public struct SpeakerLabel: Codable, Sendable, Equatable, Identifiable {
    /// Stable; the user is 0.
    public var id: Int
    public var name: String
    public var isUser: Bool
    /// `"<session>:<provider label>"`, e.g. `"2:S1"`.
    public var providerKeys: [String]

    public init(id: Int, name: String, isUser: Bool = false, providerKeys: [String] = []) {
        self.id = id
        self.name = name
        self.isUser = isUser
        self.providerKeys = providerKeys
    }
}

public struct Billing: Codable, Sendable, Equatable {
    public var engineSeconds: Double
    public var diarizationSeconds: Double
    public var costUSD: Double
    /// The summed cost of the summaries a regenerate replaced.
    public var replacedSummaryCostUSD: Double

    public init(
        engineSeconds: Double = 0,
        diarizationSeconds: Double = 0,
        costUSD: Double = 0,
        replacedSummaryCostUSD: Double = 0
    ) {
        self.engineSeconds = engineSeconds
        self.diarizationSeconds = diarizationSeconds
        self.costUSD = costUSD
        self.replacedSummaryCostUSD = replacedSummaryCostUSD
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engineSeconds = try container.decode(Double.self, forKey: .engineSeconds)
        diarizationSeconds = try container.decode(Double.self, forKey: .diarizationSeconds)
        costUSD = try container.decode(Double.self, forKey: .costUSD)
        // Absent from files written before summaries could be regenerated.
        replacedSummaryCostUSD = try container.decodeIfPresent(Double.self, forKey: .replacedSummaryCostUSD) ?? 0
    }
}

/// `meeting.json`.
public struct Meeting: Codable, Sendable, Equatable, Identifiable {
    public static let currentSchema = 1

    public var id: UUID
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    /// Excludes paused spans.
    public var durationSeconds: Double
    public var mode: MeetingMode
    public var app: String?
    public var engine: MeetingEngine
    public var userName: String
    public var speakers: [SpeakerLabel]
    public var markers: [Marker]
    public var summary: Summary?
    public var billing: Billing
    public var schema: Int
    /// Set only on a test call.
    public var test: TestCallTag?

    public init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        durationSeconds: Double = 0,
        mode: MeetingMode,
        app: String? = nil,
        engine: MeetingEngine,
        userName: String,
        speakers: [SpeakerLabel] = [],
        markers: [Marker] = [],
        summary: Summary? = nil,
        billing: Billing = Billing(),
        test: TestCallTag? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.mode = mode
        self.app = app
        self.engine = engine
        self.userName = userName
        self.speakers = speakers
        self.markers = markers
        self.summary = summary
        self.billing = billing
        schema = Self.currentSchema
        self.test = test
    }

    /// Transcription, the current summary and every summary it replaced.
    public var totalCostUSD: Double {
        billing.costUSD + billing.replacedSummaryCostUSD + (summary?.costUSD ?? 0)
    }
}

/// A meeting with its transcript and notes, as read from its folder.
public struct LoadedMeeting: Codable, Sendable, Equatable {
    public var meeting: Meeting
    public var segments: [Segment]
    public var notes: [Note]

    public init(meeting: Meeting, segments: [Segment] = [], notes: [Note] = []) {
        self.meeting = meeting
        self.segments = segments
        self.notes = notes
    }
}

/// One row of `index.json`.
public struct IndexEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var duration: Double
    public var mode: MeetingMode
    public var app: String?
    public var engine: MeetingEngine
    public var speakerCount: Int
    /// `Meeting.totalCostUSD`.
    public var costUSD: Double
    public var hasSummary: Bool
    public var audioBytes: Int
    /// `SummaryDocument.excerpt(ofSummary:)`, or else the first segment's text.
    public var excerpt: String
    public var test: TestCallTag?

    public init(
        id: UUID,
        title: String,
        startedAt: Date,
        endedAt: Date?,
        duration: Double,
        mode: MeetingMode,
        app: String?,
        engine: MeetingEngine,
        speakerCount: Int,
        costUSD: Double,
        hasSummary: Bool,
        audioBytes: Int,
        excerpt: String,
        test: TestCallTag? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.mode = mode
        self.app = app
        self.engine = engine
        self.speakerCount = speakerCount
        self.costUSD = costUSD
        self.hasSummary = hasSummary
        self.audioBytes = audioBytes
        self.excerpt = excerpt
        self.test = test
    }
}

/// The one JSON shape of every meeting file: ISO 8601 dates, one line per value.
public enum MeetingCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
