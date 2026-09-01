import AVFAudio
import MWSupport

/// `SFSpeechRecognizerAuthorizationStatus` without importing Speech; raw values match
/// the framework's.
public enum SpeechAuthorization: Int, Sendable {
    case notDetermined = 0
    case denied = 1
    case restricted = 2
    case authorized = 3
}

/// What `SFSpeechEngine` demands of a recognition request (F20: on-device, partials).
public struct RecognitionOptions: Sendable, Equatable {
    public var requiresOnDeviceRecognition: Bool
    public var shouldReportPartialResults: Bool

    public init(requiresOnDeviceRecognition: Bool, shouldReportPartialResults: Bool) {
        self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        self.shouldReportPartialResults = shouldReportPartialResults
    }
}

/// One recogniser callback, reduced to values that cross threads safely.
public enum RecognitionEvent: Sendable {
    case transcript(String, isFinal: Bool)
    case failure(AnyError)
}

/// The live request: audio goes in, `endAudio` flushes it.
public protocol RecognitionRequestHandle: Sendable {
    /// Called synchronously on the audio tap thread.
    func append(_ buffer: AVAudioPCMBuffer)
    func endAudio()
}

public enum SpeechRecognitionError: Error, Equatable, CustomStringConvertible {
    case recognizerUnavailable

    public var description: String {
        switch self {
        case .recognizerUnavailable: "on-device speech recogniser unavailable"
        }
    }
}

/// The Speech framework seam (design N5): the real calls live only in
/// `SFSpeechRecognitionBridge`, so `swift test` needs no TCC grant.
public protocol SpeechRecognitionAPI: Sendable {
    var authorizationStatus: SpeechAuthorization { get }
    /// Fire-and-forget: the grant applies from the next dictation (F23).
    func requestAuthorization()
    func startTask(
        options: RecognitionOptions,
        onResult: @escaping @Sendable (RecognitionEvent) -> Void
    ) throws -> any RecognitionRequestHandle
}
