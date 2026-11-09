import MWAudio

/// Writes a meeting's 16 kHz mono audio, the mix (remote) or the microphone (in-room), and fills
/// paused spans with silence so the file keeps meeting time (design §3 R9, R14).
public struct MeetingRecorder: Sendable {
    private let writer: any AudioFileWriting
    /// Equal rates: only the clipping and int16 scaling the streamed audio also gets.
    private var converter = PCMConverter(from: 16000, to: 16000)
    private var pausedAt: Double?

    public init(writer: any AudioFileWriting) {
        self.writer = writer
    }

    /// Samples arriving while paused are dropped; `resume(at:)` writes silence in their place.
    public mutating func write(_ samples: [Float]) throws {
        guard pausedAt == nil else { return }
        try writer.write(converter.convert(samples))
    }

    /// `time` is in meeting seconds; a second pause keeps the first one's start.
    public mutating func pause(at time: Double) {
        if pausedAt == nil { pausedAt = time }
    }

    public mutating func resume(at time: Double) throws {
        guard let start = pausedAt else { return }
        pausedAt = nil
        try writer.writeSilence(seconds: max(0, time - start))
    }

    public func finish() throws {
        try writer.finish()
    }
}
