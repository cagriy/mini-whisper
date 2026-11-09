import AVFAudio
import Foundation

public enum SystemAudioTapEvent: Sendable {
    /// The default output device changed and the tap was rebuilt on the new one.
    case defaultOutputChanged
    /// The tap could not be rebuilt and delivers nothing more.
    case stopped(any Error)
}

/// Every other process's audio output as 16 kHz mono float buffers (design §5.3).
public protocol SystemAudioTapping: Sendable {
    var events: AsyncStream<SystemAudioTapEvent> { get }
    func start(_ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

public protocol SystemAudioTapFactory: Sendable {
    /// `nil` where the system cannot tap process audio (below macOS 14.2).
    func make(excluding pid: pid_t) -> (any SystemAudioTapping)?
}

public struct CoreAudioTapFactory: SystemAudioTapFactory {
    private let isSupported: @Sendable () -> Bool

    public init(isSupported: @escaping @Sendable () -> Bool = { true }) {
        self.isSupported = isSupported
    }

    public func make(excluding pid: pid_t) -> (any SystemAudioTapping)? {
        guard isSupported(), #available(macOS 14.2, *) else { return nil }
        return SystemAudioTap(excluding: pid)
    }
}
