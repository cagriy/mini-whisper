import Foundation
import MWPipeline

/// Records the sounds the pipeline asked for, in order.
public final class FakeSoundPlayer: SoundPlaying, @unchecked Sendable {
    public enum Sound: String, Sendable, Equatable {
        case on
        case off
        case tick
    }

    private let lock = NSLock()
    private var storage: [Sound] = []

    public init() {}

    public var played: [Sound] { lock.withLock { storage } }

    public func playOn() { append(.on) }
    public func playOff() { append(.off) }
    public func playTick() { append(.tick) }

    private func append(_ sound: Sound) {
        lock.withLock { storage.append(sound) }
    }
}
