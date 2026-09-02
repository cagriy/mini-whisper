import Foundation

/// The two pre-post guards of F25 and design §5.7, carrying the overlay's wording.
/// `LocalizedError` so the pipeline's uniform `AnyError` mapping reports the same text.
public enum PasteError: LocalizedError, Equatable {
    case accessibilityLost
    case targetGone

    public var userMessage: String {
        switch self {
        case .accessibilityLost: "Accessibility permission lost — re-enable in System Settings"
        case .targetGone: "Target app is no longer running"
        }
    }

    public var errorDescription: String? { userMessage }
}
