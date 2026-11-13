import Testing

import MWMeetingPipeline
import MWMeetings
import MWSupport
import MWTestSupport
import MWUsage

@Suite struct MeetingBillingTests {
    @Test func liveCostSpeechmaticsStandard() {
        var billing = MeetingBilling(engine: .speechmaticsStandard, overrides: [:])
        #expect(billing.liveCost == 0)
        billing.add(seconds: 1800)
        billing.add(seconds: 1800)
        #expect(billing.engineSeconds == 3600)
        #expect(billing.liveCost == 0.45)
    }

    @Test func liveCostAssemblyAIIncludesDiarization() {
        var streaming = MeetingBilling(engine: .assemblyaiStreaming, overrides: [:])
        streaming.add(seconds: 600)
        #expect(streaming.liveCost == 0.045)  // 10 min × (0.0025 + 0.002)
        var pro = MeetingBilling(engine: .assemblyaiPro, overrides: [:])
        pro.add(seconds: 600)
        #expect(pro.liveCost == 0.095)  // 10 min × (0.0075 + 0.002)
    }

    @Test func finalUsageRecordsSecondsOnceUnderThePricingKey() {
        var billing = MeetingBilling(engine: .assemblyaiStreaming, overrides: [:])
        billing.add(seconds: 1200)
        #expect(billing.finalUsage() == ProviderUsage(streamedSeconds: ["assemblyai": 1200], costUSD: 0.09))
    }

    @Test func totalsCarryDiarizationSecondsOnlyForAssemblyAI() {
        var assemblyAI = MeetingBilling(engine: .assemblyaiStreaming, overrides: [:])
        assemblyAI.add(seconds: 1200)
        #expect(assemblyAI.totals == Billing(engineSeconds: 1200, diarizationSeconds: 1200, costUSD: 0.09))
        var speechmatics = MeetingBilling(engine: .speechmaticsEnhanced, overrides: [:])
        speechmatics.add(seconds: 600)
        #expect(speechmatics.totals == Billing(engineSeconds: 600, diarizationSeconds: 0, costUSD: 0.13333))
    }

    @Test func todayMinutesAreNotDoubled() async throws {
        let store = FakeUsageStore()
        var billing = MeetingBilling(engine: .assemblyaiStreaming, overrides: [:])
        billing.add(seconds: 2400)
        try await store.add(billing.finalUsage())
        let rows = Pricing.formatUsageRows(await store.totals())
        #expect(rows.today == "Today: 0/0 tok · 40m · $0.18")
        #expect(rows.month == "Month: 0/0 tok · 40m · $0.18")
    }

    @Test func summaryUsageCostsAtSonnetRates() {
        let tokens = TokenUsage(inputTokens: 12480, outputTokens: 610)
        let expected = ProviderUsage(inputTokens: 12480, outputTokens: 610, costUSD: 0.03106)
        #expect(MeetingBilling(engine: .speechmaticsStandard, overrides: [:]).summaryUsage(tokens) == expected)
        // The engine's audio and diarization rates never enter a summary's cost.
        var billing = MeetingBilling(engine: .assemblyaiPro, overrides: [:])
        billing.add(seconds: 600)
        #expect(billing.summaryUsage(tokens) == expected)
    }

    @Test func overridesApply() {
        let overrides = ["speechmatics": 0.01, "assemblyai_diarization": 0.004, "claude-sonnet-5-5_in": 3.0]
        var speechmatics = MeetingBilling(engine: .speechmaticsStandard, overrides: overrides)
        speechmatics.add(seconds: 600)
        #expect(speechmatics.liveCost == 0.1)
        var assemblyAI = MeetingBilling(engine: .assemblyaiStreaming, overrides: overrides)
        assemblyAI.add(seconds: 600)
        #expect(assemblyAI.liveCost == 0.065)
        #expect(assemblyAI.finalUsage().costUSD == 0.065)
        #expect(assemblyAI.summaryUsage(TokenUsage(inputTokens: 1_000_000)).costUSD == 3.0)
    }
}
