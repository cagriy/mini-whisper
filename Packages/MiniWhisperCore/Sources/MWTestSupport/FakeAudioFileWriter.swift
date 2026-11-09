import Foundation
import MWAudio

/// Records what a meeting recorder writes, in order, without encoding anything.
public final class FakeAudioFileWriter: AudioFileWriting, @unchecked Sendable {
    public enum Event: Sendable, Equatable {
        case write(Data)
        case silence(seconds: Double)
        case finish
    }

    private let lock = NSLock()
    private var recorded: [Event] = []

    public init() {}

    public var events: [Event] { lock.withLock { recorded } }

    public func write(_ pcm16: Data) throws {
        lock.withLock { recorded.append(.write(pcm16)) }
    }

    public func writeSilence(seconds: Double) throws {
        lock.withLock { recorded.append(.silence(seconds: seconds)) }
    }

    public func finish() throws {
        lock.withLock { recorded.append(.finish) }
    }
}
