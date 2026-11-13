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

    // MARK: - Usage table and menu rows (F31, R21)

    /// `minutes` of audio over two engines.
    private static func audio(minutes: Double) -> DayEntry {
        DayEntry(streamedSeconds: ["speechmatics": minutes * 40, "on_device": minutes * 20])
    }

    @Test func usageTableAt0_59And134Minutes() {
        let today = DayEntry(
            inputTokens: 1200, outputTokens: 340, streamedSeconds: ["on_device": 3540, "elevenlabs": 59], costUSD: 0.12
        )
        let month = DayEntry(
            inputTokens: 48_600, outputTokens: 9100, streamedSeconds: ["speechmatics": 7800, "on_device": 240],
            costUSD: 1.5
        )

        let table = Pricing.usageTable(UsageTotals(today: today, month: month))

        #expect(table.today == UsageTable.Row(tokens: "1.2k/340", audio: "59m", cost: Pricing.dollars(0.12)))
        #expect(table.month == UsageTable.Row(tokens: "48.6k/9.1k", audio: "2h 14m", cost: "$1.50"))
        let audio = [0, 0.99, 59, 59.99, 60, 134, 600].map {
            Pricing.usageTable(UsageTotals(today: Self.audio(minutes: $0))).today.audio
        }
        #expect(audio == ["0m", "0m", "59m", "59m", "1h 0m", "2h 14m", "10h 0m"])
    }

    @Test func menuRowsShowTheSameThreeFiguresForTodayAndMonth() {
        let totals = UsageTotals(
            today: DayEntry(
                inputTokens: 1200, outputTokens: 340, streamedSeconds: ["on_device": 200, "elevenlabs": 20], costUSD: 0.12
            ),
            month: DayEntry(
                inputTokens: 48_600, outputTokens: 9100, streamedSeconds: ["speechmatics": 7800, "on_device": 240],
                costUSD: 1.5
            )
        )

        let rows = Pricing.formatUsageRows(totals)

        #expect(rows.today == "Today: 1.2k/340 tok · 3m · $0.12")
        #expect(rows.month == "Month: 48.6k/9.1k tok · 2h 14m · $1.50")
        let table = Pricing.usageTable(totals)
        #expect(rows.today == "Today: \(table.today.tokens) tok · \(table.today.audio) · \(table.today.cost)")
        #expect(rows.month == "Month: \(table.month.tokens) tok · \(table.month.audio) · \(table.month.cost)")

        for (minutes, audio) in [(0.0, "0m"), (59, "59m"), (134, "2h 14m")] {
            let entry = Self.audio(minutes: minutes)
            let rows = Pricing.formatUsageRows(UsageTotals(today: entry, month: entry))
            #expect(rows.today == "Today: 0/0 tok · \(audio) · $0.00")
            #expect(rows.month == "Month: 0/0 tok · \(audio) · $0.00")
        }
    }

    @Test func emptyMonthReads0Over0() {
        let today = DayEntry(inputTokens: 500, outputTokens: 40, streamedSeconds: ["on_device": 61], costUSD: 0.02)

        let totals = UsageTotals(today: today)

        #expect(Pricing.usageTable(totals).month == UsageTable.Row(tokens: "0/0", audio: "0m", cost: "$0.00"))
        #expect(Pricing.formatUsageRows(totals).month == "Month: 0/0 tok · 0m · $0.00")
    }

    @Test func formatUsageRows() {
        let today = DayEntry(
            inputTokens: 1200,
            outputTokens: 340,
            streamedSeconds: ["on_device": 200, "elevenlabs": 20],
            costUSD: 0.12
        )
        let month = DayEntry(inputTokens: 5200, outputTokens: 900, streamedSeconds: ["on_device": 3000], costUSD: 1.5)

        let rows = Pricing.formatUsageRows(UsageTotals(today: today, month: month))

        #expect(rows.today == "Today: 1.2k/340 tok · 3m · $0.12")
        #expect(rows.month == "Month: 5.2k/900 tok · 50m · $1.50")
    }

    /// Fractions of a cent are marked, not rounded away — only a genuine zero is `$0.00`.
    @Test func formatSmallValues() {
        let today = DayEntry(inputTokens: 500, outputTokens: 40, costUSD: 0.004)

        let rows = Pricing.formatUsageRows(UsageTotals(today: today, month: today))

        #expect(rows.today == "Today: 500/40 tok · 0m · <$0.01")
        #expect(rows.month == "Month: 500/40 tok · 0m · <$0.01")
    }

    @Test func formatZero() {
        let rows = Pricing.formatUsageRows(UsageTotals())

        #expect(rows.today == "Today: 0/0 tok · 0m · $0.00")
        #expect(rows.month == "Month: 0/0 tok · 0m · $0.00")
    }

    @Test func partialMinutesFloor() {
        let today = DayEntry(streamedSeconds: ["on_device": 119])

        let rows = Pricing.formatUsageRows(UsageTotals(today: today))

        #expect(rows.today.contains(" 1m "))
    }

    @Test func thousandsAreAbbreviated() {
        let today = DayEntry(inputTokens: 3400, outputTokens: 1000)

        let rows = Pricing.formatUsageRows(UsageTotals(today: today, month: today))

        #expect(rows.today.hasPrefix("Today: 3.4k/1.0k tok"))
        #expect(rows.month.hasPrefix("Month: 3.4k/1.0k tok"))
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
        let rows = Pricing.formatUsageRows(UsageTotals(
            today: DayEntry(inputTokens: 1059, outputTokens: 103, costUSD: 0.000221),
            month: DayEntry(inputTokens: 8300, outputTokens: 912, costUSD: 0.0018)
        ))

        #expect(rows.today == "Today: 1.1k/103 tok · 0m · <$0.01")
        #expect(rows.month == "Month: 8.3k/912 tok · 0m · <$0.01")
    }
}
