import AVFAudio
import Foundation
import MWStreaming

/// The request `FakeSpeechRecognitionAPI` hands back: records what the engine appends.
public final class FakeRecognitionRequest: RecognitionRequestHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private var endCalls = 0

    public init() {}

    public var appended: [AVAudioPCMBuffer] { lock.withLock { buffers } }
    public var endAudioCalls: Int { lock.withLock { endCalls } }

    public func append(_ buffer: AVAudioPCMBuffer) { lock.withLock { buffers.append(buffer) } }
    public func endAudio() { lock.withLock { endCalls += 1 } }
}

/// Stands in for `SFSpeechRecognitionBridge`: no Speech framework, no TCC prompt.
public final class FakeSpeechRecognitionAPI: SpeechRecognitionAPI, @unchecked Sendable {
    public let authorizationStatus: SpeechAuthorization
    public let request = FakeRecognitionRequest()

    private let startError: (any Error)?
    private let lock = NSLock()
    private var authorizationRequests = 0
    private var options: [RecognitionOptions] = []
    private var handler: (@Sendable (RecognitionEvent) -> Void)?

    public init(status: SpeechAuthorization = .authorized, startError: (any Error)? = nil) {
        authorizationStatus = status
        self.startError = startError
    }

    public var requestAuthorizationCalls: Int { lock.withLock { authorizationRequests } }
    public var startOptions: [RecognitionOptions] { lock.withLock { options } }

    public func requestAuthorization() { lock.withLock { authorizationRequests += 1 } }

    public func startTask(
        options: RecognitionOptions,
        onResult: @escaping @Sendable (RecognitionEvent) -> Void
    ) throws -> any RecognitionRequestHandle {
        if let startError { throw startError }
        lock.withLock {
            self.options.append(options)
            handler = onResult
        }
        return request
    }

    /// Plays one recogniser callback into the engine.
    public func deliver(_ event: RecognitionEvent) {
        lock.withLock { handler }?(event)
    }
}
