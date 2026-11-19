import Foundation

/// Export file names from a meeting title.
public enum TitleSanitizer {
    private static let maxLength = 120

    /// "/" and ":" become "-", whitespace runs one space, trimmed, at most 120 characters.
    public static func fileStem(_ title: String) -> String {
        let words = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .split(whereSeparator: \.isWhitespace)
        let stem = String(words.joined(separator: " ").prefix(maxLength))
        return stem.trimmingCharacters(in: .whitespaces)
    }

    public static func transcriptFileName(_ title: String) -> String {
        "\(fileStem(title)) - transcript.md"
    }

    public static func summaryFileName(_ title: String) -> String {
        "\(fileStem(title)) - summary.md"
    }
}

/// The title a meeting starts with: "<front app> · <d MMM yyyy HH:mm>". A summary's subject
/// takes the name's place.
public enum MeetingTitle {
    private static let separator = " · "

    public static func `default`(app: String?, date: Date, timeZone: TimeZone = .current) -> String {
        name(app) + separator + formatter(timeZone).string(from: date)
    }

    /// Whether `title` is still the default for `app`, whatever the time zone it was made in.
    public static func isDefault(_ title: String, app: String?) -> Bool {
        let prefix = name(app) + separator
        guard title.hasPrefix(prefix) else { return false }
        return formatter(.current).date(from: String(title.dropFirst(prefix.count))) != nil
    }

    /// `subject` with the date after `title`'s last separator, or `subject` alone without one.
    public static func named(_ subject: String, from title: String) -> String {
        guard let range = title.range(of: separator, options: .backwards) else { return subject }
        return subject + title[range.lowerBound...]
    }

    private static func name(_ app: String?) -> String {
        let name = app?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Meeting" : name
    }

    private static func formatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy HH:mm"
        return formatter
    }
}
