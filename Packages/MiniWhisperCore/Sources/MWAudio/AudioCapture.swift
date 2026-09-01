public protocol AudioCapture: Sendable {
    var events: AsyncStream<AudioEvent> { get }
    func ensureRunning() async throws
    func beginCapture() async throws
    func attachListener(_ listener: (any BufferListener)?) async
    func endCapture() async -> Recording
    func scheduleIdleStop(after duration: Duration) async
    func cancelIdleStop() async
    func stop() async
}
