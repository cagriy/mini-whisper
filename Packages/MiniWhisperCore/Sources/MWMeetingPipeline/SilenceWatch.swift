import Foundation

/// When a recording meeting with no speech prompts, counts down and expires, in meeting seconds.
///
/// Each call returns the prompt change to emit, or nil when nothing changed. Expiry is final:
/// speech in the instant before the stop must not reopen anything.
struct SilenceWatch: Sendable {
    /// No prompt before this meeting time, however long the silence.
    static let grace = 180.0
    static let countdown = 60.0

    /// Seconds without speech before a prompt opens; 0 is Off.
    private(set) var threshold: Int
    private(set) var isExpired = false
    /// Paused, asleep or reconnecting: nothing can be transcribed, so no silence is inferred.
    private(set) var isSuspended = false
    /// The open or expired prompt's minutes, kept when the threshold changes under it.
    private(set) var promptMinutes = 0
    private(set) var lastSpeech = 0.0

    private var lastPartial = ""
    private var openedAt: Double?

    init(threshold: Int) {
        self.threshold = threshold
    }

    /// Engines resend the same hypothesis and send empty partials during silence; neither is speech.
    mutating func partial(_ text: String, at time: Double) -> SilencePrompt? {
        guard !isExpired else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNew = !trimmed.isEmpty && trimmed != lastPartial
        lastPartial = trimmed
        return isNew ? heard(at: time) : nil
    }

    mutating func segment(_ text: String, at time: Double) -> SilencePrompt? {
        guard !isExpired, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return heard(at: time)
    }

    /// Keep recording: silence counts again from now.
    mutating func keep(at time: Double) -> SilencePrompt? {
        guard !isExpired else { return nil }
        return heard(at: time)
    }

    mutating func suspend() -> SilencePrompt? {
        guard !isExpired else { return nil }
        isSuspended = true
        return close()
    }

    /// Silence counts from `time`, with no new grace.
    mutating func restart(at time: Double) {
        guard !isExpired else { return }
        isSuspended = false
        lastSpeech = time
    }

    /// Off closes an open prompt; any other value waits for the next one.
    mutating func setThreshold(_ seconds: Int) -> SilencePrompt? {
        guard !isExpired else { return nil }
        threshold = seconds
        return seconds == 0 ? close() : nil
    }

    mutating func tick(at time: Double) -> SilencePrompt? {
        guard !isExpired, !isSuspended else { return nil }
        if let openedAt {
            let left = openedAt + Self.countdown - time
            guard left > 0 else {
                isExpired = true
                return .expired
            }
            return .open(minutes: promptMinutes, secondsLeft: Int(ceil(left)))
        }
        guard threshold > 0, time >= Self.grace, time - lastSpeech >= Double(threshold) else { return nil }
        openedAt = time
        promptMinutes = threshold / 60
        return .open(minutes: promptMinutes, secondsLeft: Int(Self.countdown))
    }

    private mutating func heard(at time: Double) -> SilencePrompt? {
        lastSpeech = time
        return close()
    }

    private mutating func close() -> SilencePrompt? {
        guard openedAt != nil else { return nil }
        openedAt = nil
        return .closed
    }
}
