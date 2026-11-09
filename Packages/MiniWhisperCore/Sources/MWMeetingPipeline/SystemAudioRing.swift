import os

/// The latest system-audio samples (16 kHz mono), capped at two seconds (R26).
///
/// The tap thread pushes and the microphone tick takes, so the buffer is lock-guarded;
/// when the tick falls behind, the oldest samples are dropped.
public final class SystemAudioRing: Sendable {
    public static let capacity = 32_000

    private struct Storage {
        var buffer = [Float](repeating: 0, count: SystemAudioRing.capacity)
        /// Index of the oldest held sample.
        var head = 0
        var count = 0
        var peak: Float = 0
    }

    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    public init() {}

    public var count: Int { storage.withLock { $0.count } }

    public func push(_ samples: [Float]) {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        storage.withLock { state in
            state.peak = max(state.peak, peak)
            for sample in samples.suffix(Self.capacity) {
                state.buffer[(state.head + state.count) % Self.capacity] = sample
                if state.count == Self.capacity {
                    state.head = (state.head + 1) % Self.capacity
                } else {
                    state.count += 1
                }
            }
        }
    }

    /// The oldest `count` samples, removed, padded with zeros when fewer are held.
    public func take(_ count: Int) -> [Float] {
        storage.withLock { state in
            var out = [Float](repeating: 0, count: max(count, 0))
            let available = min(out.count, state.count)
            for index in 0..<available {
                out[index] = state.buffer[(state.head + index) % Self.capacity]
            }
            state.head = (state.head + available) % Self.capacity
            state.count -= available
            return out
        }
    }

    /// The loudest absolute sample pushed since the previous call (0 when none).
    public func peakSinceLastCall() -> Float {
        storage.withLock { state in
            defer { state.peak = 0 }
            return state.peak
        }
    }
}
