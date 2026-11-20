import Foundation
import MWMeetings
import MWVoices

/// Voices without the model: records `prepare` calls and every embedded window. `hold()` keeps
/// `prepare` in flight until `release()`; `prepareFailure` and `embedFailure` make those calls
/// throw. `map` turns a window into a vector; by default constant-amplitude audio is one voice,
/// `voice(amplitude:)`.
public final class FakeVoiceEmbedder: VoiceEmbedding, @unchecked Sendable {
    private let lock = NSLock()
    private let map: @Sendable ([Float]) -> VoiceVector
    private var prepares = 0
    private var recorded: [[Float]] = []
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var prepareError: (any Error)?
    private var embedError: (any Error)?

    public init(map: @escaping @Sendable ([Float]) -> VoiceVector = { FakeVoiceEmbedder.byAmplitude($0) }) {
        self.map = map
    }

    public var prepareCount: Int { lock.withLock { prepares } }

    public var windows: [[Float]] { lock.withLock { recorded } }

    public var prepareFailure: (any Error)? {
        get { lock.withLock { prepareError } }
        set { lock.withLock { prepareError = newValue } }
    }

    public var embedFailure: (any Error)? {
        get { lock.withLock { embedError } }
        set { lock.withLock { embedError = newValue } }
    }

    public func hold() {
        lock.withLock { held = true }
    }

    public func release() {
        let resumed = lock.withLock {
            held = false
            defer { waiting = [] }
            return waiting
        }
        resumed.forEach { $0.resume() }
    }

    public func prepare() async throws {
        lock.withLock { prepares += 1 }
        await withCheckedContinuation { continuation in
            let passes = lock.withLock {
                if held { waiting.append(continuation) }
                return !held
            }
            if passes { continuation.resume() }
        }
        if let error = prepareFailure { throw error }
    }

    public func embed(_ window: [Float]) async throws -> VoiceVector {
        lock.withLock { recorded.append(window) }
        if let error = embedFailure { throw error }
        return map(window)
    }

    /// The vector of constant audio at `amplitude`: the unit vector along its hundredths.
    public static func voice(amplitude: Float) -> VoiceVector {
        .unit(min(VoiceVector.dimension - 1, Int((Double(abs(amplitude)) * 100).rounded())))
    }

    /// `voice(amplitude:)` of the window's mean magnitude.
    public static func byAmplitude(_ window: [Float]) -> VoiceVector {
        let mean = window.isEmpty ? 0 : window.reduce(0.0) { $0 + Double(abs($1)) } / Double(window.count)
        return voice(amplitude: Float(mean))
    }
}

extension VoiceVector {
    /// The unit vector along `axis`.
    public static func unit(_ axis: Int) -> VoiceVector {
        padded(Array(repeating: 0, count: axis) + [1])
    }

    /// A full-length vector starting with `components`, zero after them.
    public static func padded(_ components: [Float]) -> VoiceVector {
        VoiceVector(components + Array(repeating: 0, count: dimension - components.count))
    }
}
