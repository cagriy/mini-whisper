import Foundation
import MWStats

/// Records what dictation and meetings report to the statistics record, writing nothing.
public final class FakeStatsRecorder: DictationStatsRecording, MeetingStatsRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedAttempts: [DictationAttempt] = []
    private var stoppedIDs: [UUID] = []

    public init() {}

    public var attempts: [DictationAttempt] { lock.withLock { recordedAttempts } }
    public var stopped: [UUID] { lock.withLock { stoppedIDs } }

    public func record(_ attempt: DictationAttempt) async {
        lock.withLock { recordedAttempts.append(attempt) }
    }

    public func meetingStopped(_ id: UUID) async {
        lock.withLock { stoppedIDs.append(id) }
    }
}
