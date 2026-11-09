public protocol AudioCapture: Sendable {
    var events: AsyncStream<AudioEvent> { get }
    func ensureRunning() async throws
    func beginCapture() async throws
    func attachListener(_ listener: (any BufferListener)?) async
    func endCapture() async -> Recording
    func scheduleIdleStop(after duration: Duration) async
    func cancelIdleStop() async
    func stop() async

    // Meeting mode (design §5.3).
    var meetingEvents: AsyncStream<MeetingAudioEvent> { get }
    /// While held, idle stop and sleep no longer stop the engine.
    func holdRunning(_ held: Bool) async
    /// Fed every buffer whether or not a dictation is capturing; nothing accumulates.
    func attachMeetingListener(_ listener: (any BufferListener)?) async
    /// Echo cancellation, kept across restarts.
    func setVoiceProcessing(_ on: Bool) async throws
}
