import Foundation
import MWConfig
import MWSupport
import Testing

import MWUsage

private func close(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}

/// Cost maths and the two menu rows, ported from
/// `../mini-whisper/tests/test_pricing.py` plus F35's added `speech_analyzer` rate.
@Suite struct PricingTests {
    // MARK: - Per-minute streaming rates

    @Test(arguments: [
        (EngineName.openai, "openai_realtime", 0.017),
        (EngineName.elevenlabs, "elevenlabs", 0.0065),
        (EngineName.speechmatics, "speechmatics", 0.0067),
        (EngineName.onDevice, "on_device", 0.0),
        (EngineName.speechAnalyzer, "speech_analyzer", 0.0),
    ])
    func perMinuteRates(_ engine: EngineName, _ rateKey: String, _ expected: Double) {
        #expect(Pricing.perMinute[rateKey] == expected)
        #expect(close(Pricing.dictationCost(engine: engine, seconds: 60, tokensByModel: [:]), expected))
    }

    @Test func onDeviceEnginesAreFree() {
        #expect(Pricing.dictationCost(engine: .onDevice, seconds: 600, tokensByModel: [:]) == 0)
        #expect(Pricing.dictationCost(engine: .speechAnalyzer, seconds: 600, tokensByModel: [:]) == 0)
    }

    @Test func noEngineNoMinuteCost() {
        #expect(Pricing.dictationCost(engine: nil, seconds: 60, tokensByModel: [:]) == 0)
    }

    // MARK: - Per-Mtok maths

    @Test func tokenCostTranscribe() {
        let usage = ["gpt-4o-mini-transcribe": TokenUsage(inputTokens: 1_000_000)]

        let cost = Pricing.dictationCost(engine: nil, seconds: 0, tokensByModel: usage)

        #expect(close(cost, 1.25))
        #expect(Pricing.perMTok["gpt-4o-mini-transcribe_in"] == 1.25)
    }

    @Test func tokenCostCombinedModels() {
        let usage = [
            "gpt-4o-mini-transcribe": TokenUsage(inputTokens: 2_000_000, outputTokens: 1_000_000),
            "gpt-4o-mini": TokenUsage(inputTokens: 1_000_000, outputTokens: 500_000),
        ]

        let cost = Pricing.dictationCost(engine: nil, seconds: 0, tokensByModel: usage)

        #expect(close(cost, (2 * 1.25) + (1 * 5.00) + (1 * 0.15) + (0.5 * 0.60)))
    }

    @Test func streamedPlusTokenCost() {
        let usage = ["gpt-4o-mini": TokenUsage(inputTokens: 1_000_000)]

        let cost = Pricing.dictationCost(engine: .elevenlabs, seconds: 120, tokensByModel: usage)

        #expect(close(cost, 2 * 0.0065 + 0.15))
    }

    // MARK: - Overrides and rounding

    @Test func overridePerMinute() {
        let cost = Pricing.dictationCost(
            engine: .elevenlabs, seconds: 60, tokensByModel: [:], overrides: ["elevenlabs": 0.01]
        )

        #expect(close(cost, 0.01))
    }

    @Test func overridePerMTok() {
        let cost = Pricing.dictationCost(
            engine: nil,
            seconds: 0,
            tokensByModel: ["gpt-4o-mini": TokenUsage(inputTokens: 1_000_000)],
            overrides: ["gpt-4o-mini_in": 0.30]
        )

        #expect(close(cost, 0.30))
    }

    @Test func overrideLeavesOthers() {
        let cost = Pricing.dictationCost(
            engine: .speechmatics, seconds: 60, tokensByModel: [:], overrides: ["elevenlabs": 9.99]
        )

        #expect(close(cost, 0.0067))
    }

    @Test func roundedToSixDecimals() {
        // 90 s of elevenlabs = 1.5 min × 0.0065 = 0.00975 exactly.
        #expect(Pricing.dictationCost(engine: .elevenlabs, seconds: 90, tokensByModel: [:]) == 0.00975)
    }

    // MARK: - Menu rows (F31 formats)

    @Test func formatUsageRows() {
        let today = DayEntry(
            inputTokens: 1200,
            outputTokens: 340,
            streamedSeconds: ["on_device": 200, "elevenlabs": 20],
            costUSD: 0.12
        )

        let rows = Pricing.formatUsageRows(today: today, monthCost: 1.5)

        #expect(rows.today == "Today: 1.2k/340 tok · 3m · $0.12")
        #expect(rows.month == "Month: $1.50")
    }

    @Test func formatSmallValues() {
        let today = DayEntry(inputTokens: 500, outputTokens: 40, costUSD: 0.004)

        let rows = Pricing.formatUsageRows(today: today, monthCost: 0.004)

        #expect(rows.today == "Today: 500/40 tok · 0m · $0.00")
        #expect(rows.month == "Month: $0.00")
    }

    @Test func formatZero() {
        let rows = Pricing.formatUsageRows(today: DayEntry(), monthCost: 0)

        #expect(rows.today == "Today: 0/0 tok · 0m · $0.00")
        #expect(rows.month == "Month: $0.00")
    }

    @Test func partialMinutesFloor() {
        let today = DayEntry(streamedSeconds: ["on_device": 119])

        let rows = Pricing.formatUsageRows(today: today, monthCost: 0)

        #expect(rows.today.contains(" 1m "))
    }

    @Test func thousandsAreAbbreviated() {
        let today = DayEntry(inputTokens: 3400, outputTokens: 1000)

        let rows = Pricing.formatUsageRows(today: today, monthCost: 0)

        #expect(rows.today.hasPrefix("Today: 3.4k/1.0k tok"))
    }
}
