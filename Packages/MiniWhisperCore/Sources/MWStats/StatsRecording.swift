import Foundation

public protocol DictationStatsRecording: Sendable {
    func record(_ attempt: DictationAttempt) async
}

public protocol MeetingStatsRecording: Sendable {
    func meetingStopped(_ id: UUID) async
}

/// One dictation attempt, whatever ended it: every attempt is recorded exactly once.
public struct DictationAttempt: Sendable, Equatable {
    /// Raw values are what `dictations.jsonl` stores.
    public enum Outcome: String, Sendable, Codable, CaseIterable {
        case delivered
        case tooShort = "too_short"
        case silent
        case superseded
        case noKey = "no_key"
        case empty
        case failed
        case micError = "mic_error"
        case deviceChanged = "device_changed"
        case aborted
    }

    /// The history entry's id when delivered.
    public var id: String
    public var bundleID: String?
    /// `nil` for a batch-only dictation.
    public var engine: String?
    /// Recording length.
    public var seconds: Double
    /// 0 unless delivered.
    public var words: Int
    public var outcome: Outcome
    /// Key release to the paste returning; delivered attempts only.
    public var wait: Double?
    public var costUSD: Double

    public init(
        id: String,
        bundleID: String?,
        engine: String?,
        seconds: Double,
        words: Int,
        outcome: Outcome,
        wait: Double?,
        costUSD: Double
    ) {
        self.id = id
        self.bundleID = bundleID
        self.engine = engine
        self.seconds = seconds
        self.words = words
        self.outcome = outcome
        self.wait = wait
        self.costUSD = costUSD
    }
}
