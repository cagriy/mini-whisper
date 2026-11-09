import Foundation
import MWConfig
import MWSupport
import Testing

import MWUsage

private func close(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance
}

/// Cost maths and the two menu rows, ported from
/// `../mini-whisper-py/tests/test_pricing.py` plus F35's added `speech_analyzer` rate.
@Suite struct PricingTests {
    // MARK: - Per-minute streaming rates

    @Test(arguments: [
        (EngineName.openai, "openai_realtime", 0.017),
        (EngineName.elevenlabs, "elevenlabs", 0.0065),
        (EngineName.speechmatics, "speechmatics", 0.0075),
        (EngineName.assemblyai, "assemblyai", 0.0025),
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

        #expect(close(cost, 0.0075))
    }

    @Test func roundedToSixDecimals() {
        // 90 s of elevenlabs = 1.5 min × 0.0065 = 0.00975 exactly.
        #expect(Pricing.dictationCost(engine: .elevenlabs, seconds: 90, tokensByModel: [:]) == 0.00975)
    }

    // MARK: - Meetings (R2, R18)

    @Test(arguments: [
        ("speechmatics_enhanced", 0.013333),
        ("assemblyai", 0.0025),
        ("assemblyai_pro", 0.0075),
        ("assemblyai_diarization", 0.002),
    ])
    func meetingRatesPerMinute(_ key: String, _ expected: Double) {
        #expect(Pricing.perMinute[key] == expected)
    }

    @Test func sonnetRatesPerMTok() {
        #expect(Pricing.perMTok["claude-sonnet-5-5_in"] == 2.00)
        #expect(Pricing.perMTok["claude-sonnet-5-5_out"] == 10.00)
    }

    @Test func meetingCostSpeechmaticsStandardOneHourIs45Cents() {
        let cost = Pricing.meetingCost(
            engine: .speechmaticsStandard, seconds: 3600, tokens: TokenUsage(), overrides: [:]
        )

        #expect(close(cost, 0.45))
    }

    @Test func meetingCostAssemblyAIAddsDiarization() {
        let cost = Pricing.meetingCost(
            engine: .assemblyaiStreaming, seconds: 3600, tokens: TokenUsage(), overrides: [:]
        )

        #expect(close(cost, 0.15 + 0.12))
    }

    @Test func meetingCostIncludesSummaryTokens() {
        let cost = Pricing.meetingCost(
            engine: .speechmaticsStandard,
            seconds: 0,
            tokens: TokenUsage(inputTokens: 1_000_000, outputTokens: 100_000),
            overrides: [:]
        )

        #expect(close(cost, 2.00 + 1.00))
    }

    @Test func meetingCostHonoursOverridesOfEveryNewKey() {
        let overrides = [
            "speechmatics": 0.01,
            "speechmatics_enhanced": 0.02,
            "assemblyai": 0.03,
            "assemblyai_pro": 0.04,
            "assemblyai_diarization": 0.005,
            "claude-sonnet-5-5_in": 3.00,
            "claude-sonnet-5-5_out": 15.00,
        ]
        func oneMinute(_ engine: MeetingEngine) -> Double {
            Pricing.meetingCost(engine: engine, seconds: 60, tokens: TokenUsage(), overrides: overrides)
        }

        let summary = Pricing.meetingCost(
            engine: .speechmaticsStandard,
            seconds: 0,
            tokens: TokenUsage(inputTokens: 1_000_000, outputTokens: 1_000_000),
            overrides: overrides
        )

        #expect(close(oneMinute(.speechmaticsStandard), 0.01))
        #expect(close(oneMinute(.speechmaticsEnhanced), 0.02))
        #expect(close(oneMinute(.assemblyaiStreaming), 0.035))
        #expect(close(oneMinute(.assemblyaiPro), 0.045))
        #expect(close(summary, 18.00))
    }

    @Test func perHourMatchesTheChooserLabels() {
        #expect(Pricing.perHour(.speechmaticsStandard, overrides: [:]) == 0.45)
        #expect(Pricing.perHour(.speechmaticsEnhanced, overrides: [:]) == 0.80)
        #expect(Pricing.perHour(.assemblyaiStreaming, overrides: [:]) == 0.27)
        #expect(Pricing.perHour(.assemblyaiPro, overrides: [:]) == 0.57)
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

    /// Fractions of a cent are marked, not rounded away — only a genuine zero is `$0.00`.
    @Test func formatSmallValues() {
        let today = DayEntry(inputTokens: 500, outputTokens: 40, costUSD: 0.004)

        let rows = Pricing.formatUsageRows(today: today, monthCost: 0.004)

        #expect(rows.today == "Today: 500/40 tok · 0m · <$0.01")
        #expect(rows.month == "Month: <$0.01")
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

    /// A cleanup call costs about $0.00004, so rounding it to `$0.000` reads as free
    /// when it is not. Anything too small to show at the given precision says so.
    @Test func amountsBelowThePrecisionAreMarkedRatherThanRoundedToZero() {
        #expect(Pricing.dollars(0, decimals: 3) == "$0.000")
        #expect(Pricing.dollars(0.000042, decimals: 3) == "<$0.001")
        #expect(Pricing.dollars(0.0006, decimals: 3) == "$0.001")
        #expect(Pricing.dollars(1.5) == "$1.50")
        #expect(Pricing.dollars(0.00022) == "<$0.01")
    }

    @Test func menuRowsMarkASubCentDay() {
        let rows = Pricing.formatUsageRows(
            today: DayEntry(inputTokens: 1059, outputTokens: 103, costUSD: 0.000221),
            monthCost: 0.0018
        )

        #expect(rows.today == "Today: 1.1k/103 tok · 0m · <$0.01")
        #expect(rows.month == "Month: <$0.01")
    }
}
