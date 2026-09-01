import Foundation

/// User-facing description for an arbitrary error — F14's "other failures → the error's
/// description". Falls back to domain and code when the error carries no message.
public struct AnyError: Error, CustomStringConvertible, Sendable {
    public let description: String

    public init(_ error: any Error) {
        if let localized = (error as? any LocalizedError)?.errorDescription {
            description = localized
            return
        }
        let nsError = error as NSError
        if nsError.userInfo[NSLocalizedDescriptionKey] != nil {
            description = nsError.localizedDescription
        } else {
            description = "\(nsError.domain) \(nsError.code)"
        }
    }
}
