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

/// The title a meeting starts with: "<front app> · <d MMM yyyy HH:mm>".
public enum MeetingTitle {
    public static func `default`(app: String?, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy HH:mm"
        let name = app?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(name.isEmpty ? "Meeting" : name) · \(formatter.string(from: date))"
    }
}
