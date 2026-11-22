import Foundation

public enum MeetingTextEscaping {
    /// Text inside a block cannot close it early: `</tag` becomes `<\/tag`.
    public static func escaped(_ text: String, closing tag: String) -> String {
        text.replacingOccurrences(of: "</\(tag)", with: "<\\/\(tag)", options: .caseInsensitive)
    }
}
