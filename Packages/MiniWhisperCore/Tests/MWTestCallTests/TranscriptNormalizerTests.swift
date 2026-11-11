import Testing

import MWTestCall

@Suite struct TranscriptNormalizerTests {
    private static let table: [(String, String)] = [
        // Case and punctuation.
        ("The Plan", "the plan"),
        ("fail, on staging.", "fail on staging"),
        ("(Priya) asked: why?!", "priya asked why"),
        // Apostrophes inside words survive; quotes around a word do not.
        ("it's", "it's"),
        ("it’s", "it's"),
        ("'quoted'", "quoted"),
        // Hyphens and dashes split.
        ("one-line", "one line"),
        ("pre‐flight", "pre flight"),
        ("ready — mostly", "ready mostly"),
        ("14:00–16:00", "fourteen sixteen"),
        // Integers.
        ("40", "forty"),
        ("0", "zero"),
        ("7", "seven"),
        ("13", "thirteen"),
        ("105", "one hundred five"),
        ("1,200", "one thousand two hundred"),
        ("2,500,017", "two million five hundred thousand seventeen"),
        ("40,", "forty"),
        // Decimals.
        ("3.2", "three point two"),
        ("0.25", "zero point two five"),
        // Percentages.
        ("80%", "eighty percent"),
        ("3.5%", "three point five percent"),
        // Ordinals.
        ("14th", "fourteenth"),
        ("1st", "first"),
        ("2nd", "second"),
        ("3rd", "third"),
        ("21st", "twenty first"),
        ("12th", "twelfth"),
        ("30th", "thirtieth"),
        // Times.
        ("10:30", "ten thirty"),
        ("9:05", "nine oh five"),
        ("10:00", "ten"),
        // Currency.
        ("$40", "forty dollars"),
        ("$3.50", "three dollars fifty"),
        ("$1", "one dollar"),
        ("$1,200.", "one thousand two hundred dollars"),
        // Years: bare four-digit integers from 1100 to 2099.
        ("2026", "twenty twenty six"),
        ("2005", "two thousand five"),
        ("2000", "two thousand"),
        ("1999", "nineteen ninety nine"),
        ("1905", "nineteen oh five"),
        ("1900", "nineteen hundred"),
        ("2100", "two thousand one hundred"),
        // Mixed.
        (
            "On the 14th at 10:30, we're 80% done: $3.50 a seat, 1,200 seats, 3.2 releases in 2026 — a one-line fix.",
            """
            on the fourteenth at ten thirty we're eighty percent done three dollars fifty a seat one thousand \
            two hundred seats three point two releases in twenty twenty six a one line fix
            """
        ),
    ]

    @Test(arguments: table)
    func normalises(_ input: String, _ expected: String) {
        #expect(TranscriptNormalizer().tokens(input) == expected.split(separator: " ").map(String.init))
    }

    @Test func emptyAndPunctuationOnlyGiveNoTokens() {
        #expect(TranscriptNormalizer().tokens("") == [])
        #expect(TranscriptNormalizer().tokens(" — ... ") == [])
    }

    @Test func scriptAndTranscriptFormsAgree() {
        let normalizer = TranscriptNormalizer()

        #expect(
            normalizer.tokens("the payments migration is at eighty percent")
                == normalizer.tokens("The payments migration is at 80%.")
        )
        #expect(
            normalizer.tokens("sprint fourteen starts on the third at nine oh five")
                == normalizer.tokens("Sprint 14 starts on the 3rd at 9:05.")
        )
    }

    @Test func sourcedTokensKeepTheirWord() {
        let sourced = TranscriptNormalizer().sourced("80% done")

        #expect(sourced == [
            SourcedToken(token: "eighty", wordIndex: 0, word: "80%"),
            SourcedToken(token: "percent", wordIndex: 0, word: "80%"),
            SourcedToken(token: "done", wordIndex: 1, word: "done"),
        ])
    }

    @Test func sourcedWordIndicesCountEveryWordEvenWithoutTokens() {
        let sourced = TranscriptNormalizer().sourced("web-hook — fixed")

        #expect(sourced.map(\.token) == ["web", "hook", "fixed"])
        #expect(sourced.map(\.wordIndex) == [0, 0, 2])
        #expect(sourced.map(\.word) == ["web-hook", "web-hook", "fixed"])
    }
}
