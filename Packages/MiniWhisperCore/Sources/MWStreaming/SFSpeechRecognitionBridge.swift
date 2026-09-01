import AVFAudio
import Foundation
import MWSupport
import Speech

/// The only file in MWStreaming that talks to `SFSpeechRecognizer` (design N5).
public struct SFSpeechRecognitionBridge: SpeechRecognitionAPI {
    public init() {}

    public var authorizationStatus: SpeechAuthorization {
        SpeechAuthorization(rawValue: SFSpeechRecognizer.authorizationStatus().rawValue) ?? .denied
    }

    public func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    public func startTask(
        options: RecognitionOptions,
        onResult: @escaping @Sendable (RecognitionEvent) -> Void
    ) throws -> any RecognitionRequestHandle {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = options.requiresOnDeviceRecognition
        request.shouldReportPartialResults = options.shouldReportPartialResults

        let task = recognizer.recognitionTask(with: request) { result, error in
            if let error {
                onResult(.failure(AnyError(error)))
            } else if let result {
                onResult(.transcript(result.bestTranscription.formattedString, isFinal: result.isFinal))
            }
        }
        return Handle(recognizer: recognizer, request: request, task: task)
    }

    /// Retains the session for as long as the engine holds the handle.
    /// `@unchecked`: `append` and `endAudio` are the only calls made, from the audio
    /// tap thread, and the request serialises them itself.
    private struct Handle: RecognitionRequestHandle, @unchecked Sendable {
        let recognizer: SFSpeechRecognizer
        let request: SFSpeechAudioBufferRecognitionRequest
        let task: SFSpeechRecognitionTask

        func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
        func endAudio() { request.endAudio() }
    }
}
