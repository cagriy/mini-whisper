import Foundation

public enum NameFold {
    public static func key(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
