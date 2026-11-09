import Foundation
import MWMeetings

public enum MeetingIDError: Error, Equatable, LocalizedError {
    case invalid(String)
    case notFound(String)
    case ambiguous(String)
    /// The index could not be read; carries the reason.
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let id): "invalid meeting id \(id): use a UUID or at least its first 8 hex characters"
        case .notFound(let id): "no meeting \(id)"
        case .ambiguous(let id): "ambiguous meeting id \(id)"
        case .unreadable(let reason): "could not read the meetings index: \(reason)"
        }
    }
}

/// Agent-supplied meeting ids (design §5.8): a full UUID, or an unambiguous prefix of at
/// least 8 hex characters. The text is validated before the index is read, and a path is
/// only ever built from the resolved `UUID`.
public enum MeetingID {
    public static let minimumPrefixDigits = 8

    public static func resolve(_ text: String, in reader: any MeetingReading) -> Result<UUID, MeetingIDError> {
        let exact = UUID(uuidString: text)
        guard exact != nil || isPrefix(text) else { return .failure(.invalid(text)) }

        let ids: [UUID]
        do {
            ids = try reader.index().map(\.id)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        if let exact {
            return ids.contains(exact) ? .success(exact) : .failure(.notFound(text))
        }
        let prefix = text.lowercased()
        let matches = ids.filter { $0.uuidString.lowercased().hasPrefix(prefix) }
        switch matches.count {
        case 0: return .failure(.notFound(text))
        case 1: return .success(matches[0])
        default: return .failure(.ambiguous(text))
        }
    }

    /// ASCII hex digits and the UUID's hyphens, no longer than a UUID, with enough digits.
    private static func isPrefix(_ text: String) -> Bool {
        let isDigit = { (character: Character) in character.isASCII && character.isHexDigit }
        return text.count <= 36
            && text.allSatisfy { $0 == "-" || isDigit($0) }
            && text.filter(isDigit).count >= minimumPrefixDigits
    }
}
