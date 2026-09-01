import Foundation
import MWConfig
import MWTestSupport
import Testing

import MWUsage

/// Per-day accumulation, month pruning and totals over a real `ConfigStore` in a temp
/// directory, ported from the usage cases in `../mini-whisper/tests/test_config.py`.
@Suite struct UsageStoreTests {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func date(_ day: String) throws -> Date {
        try #require(Self.dayFormatter.date(from: day))
    }

    private func store(_ directory: TempDirectory, today: String = "2026-09-15") throws -> UsageStore {
        let fixed = try date(today)
        return UsageStore(config: ConfigStore(directory: directory.url), today: { fixed })
    }

    @Test func addAccumulatesIntoToday() async throws {
        let directory = try TempDirectory()
        let store = try store(directory)

        var entry = try await store.add(ProviderUsage(
            inputTokens: 10, outputTokens: 5, streamedSeconds: ["on_device": 30], costUSD: 0.02
        ))
        #expect(entry == DayEntry(
            inputTokens: 10, outputTokens: 5, streamedSeconds: ["on_device": 30], costUSD: 0.02
        ))

        entry = try await store.add(ProviderUsage(
            inputTokens: 3,
            outputTokens: 2,
            streamedSeconds: ["on_device": 10, "elevenlabs": 5],
            costUSD: 0.01
        ))

        #expect(entry.inputTokens == 13)
        #expect(entry.outputTokens == 7)
        #expect(entry.streamedSeconds == ["on_device": 40, "elevenlabs": 5])
        #expect(abs(entry.costUSD - 0.03) < 1e-9)
    }

    @Test func addDefaultsMissingFields() async throws {
        let directory = try TempDirectory()

        let entry = try await store(directory).add(ProviderUsage(inputTokens: 4, outputTokens: 6))

        #expect(entry == DayEntry(inputTokens: 4, outputTokens: 6))
    }

    @Test func addWritesThroughToConfigJSON() async throws {
        let directory = try TempDirectory()

        _ = try await store(directory).add(ProviderUsage(inputTokens: 4, costUSD: 0.5))

        let data = try Data(contentsOf: directory.file("config.json"))
        let config = try JSONDecoder().decode(Config.self, from: data)
        #expect(config.usage["2026-09-15"] == DayEntry(inputTokens: 4, costUSD: 0.5))
    }

    @Test func addPrunesPreviousMonthKeepsCurrent() async throws {
        let directory = try TempDirectory()
        let earlierThisMonth = DayEntry(inputTokens: 5, outputTokens: 5, costUSD: 0.10)
        let lastMonth = DayEntry(inputTokens: 99, outputTokens: 99, costUSD: 9.99)
        let config = ConfigStore(directory: directory.url)
        try await config.update {
            $0.usage = ["2026-09-10": earlierThisMonth, "2026-08-31": lastMonth]
        }
        let fixed = try date("2026-09-15")
        let store = UsageStore(config: config, today: { fixed })

        _ = try await store.add(ProviderUsage(inputTokens: 1, outputTokens: 1))

        let usage = await config.load().usage
        #expect(usage["2026-08-31"] == nil)
        #expect(usage["2026-09-10"] == earlierThisMonth)
        #expect(usage["2026-09-15"]?.inputTokens == 1)
    }

    @Test func totalsSumMonth() async throws {
        let directory = try TempDirectory()
        let config = ConfigStore(directory: directory.url)
        let today = DayEntry(
            inputTokens: 20, outputTokens: 30, streamedSeconds: ["on_device": 60], costUSD: 0.05
        )
        try await config.update {
            $0.usage = [
                "2026-09-10": DayEntry(inputTokens: 5, outputTokens: 5, costUSD: 0.10),
                "2026-09-15": today,
                "2026-08-31": DayEntry(costUSD: 9.99),
            ]
        }
        let fixed = try date("2026-09-15")
        let store = UsageStore(config: config, today: { fixed })

        let totals = await store.totals()

        #expect(totals.today == today)
        #expect(abs(totals.monthCost - 0.15) < 1e-9)
    }

    @Test func totalsEmpty() async throws {
        let directory = try TempDirectory()

        let totals = await (try store(directory)).totals()

        #expect(totals.today == DayEntry())
        #expect(totals.monthCost == 0)
    }

    @Test func concurrentAddsSerialise() async throws {
        let directory = try TempDirectory()
        let store = try store(directory)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = try? await store.add(ProviderUsage(inputTokens: 1, outputTokens: 1, costUSD: 0.01))
                }
            }
        }

        let totals = await store.totals()
        #expect(totals.today.inputTokens == 20)
        #expect(totals.today.outputTokens == 20)
        #expect(abs(totals.today.costUSD - 0.20) < 1e-9)
    }
}
