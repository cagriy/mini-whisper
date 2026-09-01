import Foundation

/// Monotonic time plus cancellable sleeping, injected everywhere a duration matters
/// so tests can drive time deterministically (design §5.12).
public protocol Clock: Sendable {
    var now: TimeInterval { get }
    func sleep(for duration: Duration) async throws
}

public struct SystemClock: Clock {
    private static let origin = ContinuousClock.now

    public init() {}

    public var now: TimeInterval { (ContinuousClock.now - Self.origin).seconds }

    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

extension Duration {
    public var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
