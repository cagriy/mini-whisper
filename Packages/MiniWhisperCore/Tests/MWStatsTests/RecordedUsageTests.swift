import Foundation
import MWConfig
import MWTestSupport
import MWUsage
import Testing

import MWStats

@Suite struct RecordedUsageTests {
    private struct Refused: Error {}

    private struct RefusingUsage: UsageRecording {
        func add(_ usage: ProviderUsage) async throws -> DayEntry { throw Refused() }
        func totals() async -> UsageTotals { UsageTotals() }
    }

    private func stats(_ temp: TempDirectory) async throws -> StatsStore {
        let now = try #require(StatsTime.parse("2026-11-30T09:14:03+00:00")).date
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let store = StatsStore(directory: temp.url, now: { now }, calendar: { [utc] in utc })
        await store.open()
        return store
    }

    private func usage(_ purpose: UsagePurpose) -> ProviderUsage {
        ProviderUsage(
            purpose: purpose, inputTokens: 10, outputTokens: 2, streamedSeconds: ["elevenlabs": 30], costUSD: 0.05
        )
    }

    @Test(arguments: [UsagePurpose.dictation, .meeting, .summary, .naming])
    func eachPurposeReachesItsDaySpendAndTheBase(_ purpose: UsagePurpose) async throws {
        let temp = try TempDirectory()
        let store = try await stats(temp)
        let base = FakeUsageStore()

        let entry = try await RecordedUsage(base: base, stats: store).add(usage(purpose))

        #expect(await store.snapshot().days == [DayRow(
            day: "2026-11-30",
            spend: [purpose.rawValue: Spend(usd: 0.05, tokensIn: 10, tokensOut: 2, seconds: ["elevenlabs": 30])]
        )])
        #expect(base.added == [usage(purpose)])
        #expect(entry == DayEntry(inputTokens: 10, outputTokens: 2, streamedSeconds: ["elevenlabs": 30], costUSD: 0.05))
    }

    @Test func aTestCallReachesTheBaseButNoDayLine() async throws {
        let temp = try TempDirectory()
        let store = try await stats(temp)
        let base = FakeUsageStore()

        try await RecordedUsage(base: base, stats: store).add(usage(.testCall))

        #expect(base.added == [usage(.testCall)])
        #expect(await store.snapshot().days.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: temp.file("days.jsonl").path))
    }

    @Test func aThrowingBaseStillRecordsTheSpendThenTheErrorIsRethrown() async throws {
        let temp = try TempDirectory()
        let store = try await stats(temp)

        await #expect(throws: Refused.self) {
            try await RecordedUsage(base: RefusingUsage(), stats: store).add(usage(.meeting))
        }

        #expect(await store.snapshot().days.first?.spend["meeting"]?.usd == 0.05)
    }

    @Test func totalsAreTheBases() async throws {
        let temp = try TempDirectory()
        let base = FakeUsageStore(today: DayEntry(costUSD: 1), month: DayEntry(inputTokens: 4, costUSD: 3))

        let totals = await RecordedUsage(base: base, stats: try await stats(temp)).totals()

        #expect(totals == UsageTotals(today: DayEntry(costUSD: 1), month: DayEntry(inputTokens: 4, costUSD: 3)))
    }
}
