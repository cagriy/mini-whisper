import Foundation
import MWSupport

/// Every batch-path failure, with F14's user-facing message. `LocalizedError` so the
/// pipeline's uniform `AnyError` mapping reports the same text.
public enum APIError: LocalizedError {
    case httpStatus(Int)
    case transport(any Error)
    case emptyAudio

    public var userMessage: String {
        switch self {
        case .httpStatus(401): "Invalid API key — please update in Settings."
        case .httpStatus(429): "Rate limited — please wait and try again."
        case .httpStatus(let code): "API error (\(code))."
        case .transport(let error): AnyError(error).description
        case .emptyAudio: "Audio buffer is empty"
        }
    }

    public var errorDescription: String? { userMessage }
}
