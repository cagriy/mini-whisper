/// A comparable token and the whitespace-delimited word it came from, in its original spelling.
public struct SourcedToken: Sendable, Equatable {
    public var token: String
    /// The word's position among the text's whitespace-separated words.
    public var wordIndex: Int
    public var word: String

    public init(token: String, wordIndex: Int, word: String) {
        self.token = token
        self.wordIndex = wordIndex
        self.word = word
    }
}

/// Text to comparable tokens (design R14). Script and transcript go through this one function,
/// so digits an engine writes meet the script's spelled-out words. The spoken forms are a
/// contract: changing one moves every stored WER.
public struct TranscriptNormalizer: Sendable {
    public init() {}

    public func tokens(_ text: String) -> [String] {
        sourced(text).map(\.token)
    }

    public func sourced(_ text: String) -> [SourcedToken] {
        var result: [SourcedToken] = []
        for (index, word) in text.split(whereSeparator: \.isWhitespace).enumerated() {
            let lowered = word.lowercased().replacingOccurrences(of: "’", with: "'")
            for piece in lowered.split(whereSeparator: Self.dashes.contains) {
                for token in Self.tokens(ofPiece: piece) {
                    result.append(SourcedToken(token: token, wordIndex: index, word: String(word)))
                }
            }
        }
        return result
    }

    private static let dashes: Set<Character> = ["-", "‐", "–", "—"]

    private static func tokens(ofPiece piece: Substring) -> [String] {
        var trimmed = piece
        while let first = trimmed.first, !(first.isLetter || first.isNumber || first == "$") { trimmed.removeFirst() }
        while let last = trimmed.last, !(last.isLetter || last.isNumber || last == "%") { trimmed.removeLast() }
        if let spoken = spokenNumber(trimmed) { return spoken }
        var word = String(trimmed.filter { $0.isLetter || $0.isNumber || $0 == "'" })
        while word.hasPrefix("'") { word.removeFirst() }
        while word.hasSuffix("'") { word.removeLast() }
        return word.isEmpty ? [] : [word]
    }

    // MARK: - Numbers

    private static func spokenNumber(_ text: Substring) -> [String]? {
        if let match = text.wholeMatch(of: /([0-9]{1,2}):([0-9]{2})/),
           let hour = Int(match.1), let minute = Int(match.2), hour <= 24, minute < 60 {
            return cardinal(hour) + (minute == 0 ? [] : tail(minute))
        }
        if let match = text.wholeMatch(of: /([0-9]+)(?:st|nd|rd|th)/) {
            return ordinal(cardinal(match.1))
        }
        if let match = text.wholeMatch(of: /\$([0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.([0-9]+))?/) {
            let (whole, fraction) = (match.1, match.2)
            let unit = Int(whole) == 1 ? "dollar" : "dollars"
            guard let fraction else { return cardinal(whole) + [unit] }
            guard fraction.count == 2, let cents = Int(fraction) else { return decimal(whole, fraction) + ["dollars"] }
            return cardinal(whole) + [unit] + (cents == 0 ? [] : cardinal(cents))
        }
        guard let match = text.wholeMatch(of: /([0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.([0-9]+))?(%)?/) else {
            return nil
        }
        let (whole, fraction, percent) = (match.1, match.2, match.3)
        let number: [String]
        if let fraction {
            number = decimal(whole, fraction)
        } else if percent == nil, whole.count == 4, let year = Int(whole), (1100...2099).contains(year) {
            number = Self.year(year)
        } else {
            number = cardinal(whole)
        }
        return number + (percent == nil ? [] : ["percent"])
    }

    private static let ones = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
    ]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    private static let scales = [
        (1_000_000_000_000, "trillion"), (1_000_000_000, "billion"), (1_000_000, "million"), (1_000, "thousand"),
    ]
    private static let irregularOrdinals = [
        "one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth", "nine": "ninth",
        "twelve": "twelfth",
    ]

    /// Digits with optional thousands commas; beyond the scales, digit by digit.
    private static func cardinal(_ digits: Substring) -> [String] {
        let plain = digits.filter { $0 != "," }
        guard plain.count <= 15, let number = Int(plain) else { return plain.map { ones[$0.wholeNumberValue!] } }
        return cardinal(number)
    }

    private static func cardinal(_ number: Int) -> [String] {
        guard number > 0 else { return ["zero"] }
        var words: [String] = []
        var rest = number
        for (scale, name) in scales where rest >= scale {
            words += belowThousand(rest / scale) + [name]
            rest %= scale
        }
        return words + belowThousand(rest)
    }

    /// Empty for zero.
    private static func belowThousand(_ number: Int) -> [String] {
        var words: [String] = []
        if number >= 100 { words += [ones[number / 100], "hundred"] }
        let rest = number % 100
        if rest >= 20 {
            words.append(tens[rest / 10])
            if rest % 10 > 0 { words.append(ones[rest % 10]) }
        } else if rest > 0 {
            words.append(ones[rest])
        }
        return words
    }

    private static func ordinal(_ words: [String]) -> [String] {
        guard let last = words.last else { return words }
        let ordinal = irregularOrdinals[last] ?? (last.hasSuffix("y") ? String(last.dropLast()) + "ieth" : last + "th")
        return Array(words.dropLast()) + [ordinal]
    }

    private static func decimal(_ whole: Substring, _ fraction: Substring) -> [String] {
        cardinal(whole) + ["point"] + fraction.map { ones[$0.wholeNumberValue!] }
    }

    /// "twenty twenty six", "nineteen oh five", "nineteen hundred"; 2000–2009 as "two thousand five".
    private static func year(_ year: Int) -> [String] {
        if (2000...2009).contains(year) { return cardinal(year) }
        let low = year % 100
        return cardinal(year / 100) + (low == 0 ? ["hundred"] : tail(low))
    }

    /// The last two digits of a year or a time, 1–99: "oh five", "thirty".
    private static func tail(_ number: Int) -> [String] {
        number < 10 ? ["oh", ones[number]] : cardinal(number)
    }
}
