import Foundation
import Testing

import MWStats

@Suite struct StatFormatTests {
    // Not en_US_POSIX: it groups no thousands, so it could never show `9,999`.
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    // Rounding is half away from zero, and a value that rounds up to the next form takes it.
    @Test(arguments: [
        (0, "0"), (9_999, "9,999"), (9_999.4, "9,999"), (9_999.5, "10k"), (10_000, "10k"),
        (86_400, "86.4k"), (86_450, "86.5k"), (999_949, "999.9k"), (999_950, "1M"),
        (1_000_000, "1M"), (1_420_000, "1.42M"), (1_425_000, "1.43M"), (1_500_000, "1.5M"),
    ] as [(Double, String)])
    func pageNumbers(_ value: Double, _ expected: String) {
        #expect(StatFormat.pageNumber(value, locale: english) == expected)
    }

    @Test(arguments: [
        (0, "0"), (999, "999"), (999.4, "999"), (999.5, "1k"), (1_000, "1k"), (8_400, "8.4k"),
        (8_450, "8.5k"), (99_949, "99.9k"), (99_950, "100k"), (126_000, "126k"), (126_500, "127k"),
        (999_499, "999k"), (999_500, "1M"), (1_400_000, "1.4M"), (1_450_000, "1.5M"),
    ] as [(Double, String)])
    func sidebarNumbers(_ value: Double, _ expected: String) {
        #expect(StatFormat.sidebarNumber(value, locale: english) == expected)
    }

    @Test func countsFormatAsTheirValue() {
        let words: Int = 1_420_000
        let dictations: Int = 126_000

        #expect(StatFormat.pageNumber(words, locale: english) == "1.42M")
        #expect(StatFormat.sidebarNumber(dictations, locale: english) == "126k")
    }

    @Test(arguments: [
        (0, "0 m"), (29, "0 m"), (30, "1 m"), (2_520, "42 m"), (3_569, "59 m"), (3_570, "1 h"),
        (6_600, "1 h 50 m"), (7_200, "2 h"), (35_940, "9 h 59 m"), (35_970, "10 h"),
        (36_180, "10.1 h"), (52_020, "14.5 h"), (52_200, "14.5 h"), (359_784, "99.9 h"),
        (359_820, "100 h"), (674_640, "187 h"), (675_000, "188 h"), (4_442_400, "1,234 h"),
    ] as [(TimeInterval, String)])
    func durations(_ seconds: TimeInterval, _ expected: String) {
        #expect(StatFormat.duration(seconds, locale: english) == expected)
    }

    @Test func theLocaleGroupsThousandsAndMarksDecimals() {
        #expect(StatFormat.pageNumber(9_999, locale: german) == "9.999")
        #expect(StatFormat.pageNumber(86_400, locale: german) == "86,4k")
        #expect(StatFormat.sidebarNumber(8_400, locale: german) == "8,4k")
        #expect(StatFormat.duration(52_200, locale: german) == "14,5 h")
        #expect(StatFormat.duration(4_442_400, locale: german) == "1.234 h")
    }

    @Test(arguments: [(0, "$0.00"), (1.5, "$1.50"), (0.004, "<$0.01"), (48.204, "$48.20")] as [(Double, String)])
    func moneyReadsAsPricingDollars(_ usd: Double, _ expected: String) {
        #expect(StatFormat.money(usd) == expected)
    }
}
