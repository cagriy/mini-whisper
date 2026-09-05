import Foundation
import MWConfig
import MWHistory
import MWPaste
import MWPipeline
import MWSupport
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct HistoryListModelTests {
    private final class EventLog: @unchecked Sendable {
        private(set) var events: [String] = []

        func record(_ event: String) { events.append(event) }
    }

    private final class RecordingPaster: Pasting, @unchecked Sendable {
        let log: EventLog
        private(set) var pastes: [(text: String, pid: pid_t, submit: SubmitKey?)] = []

        init(log: EventLog) { self.log = log }

        func paste(_ text: String, into pid: pid_t, submit: SubmitKey?) async throws {
            pastes.append((text, pid, submit))
            log.record("paste(\(pid))")
        }
    }

    private final class RecordingPasteboard: PasteboardAccess, @unchecked Sendable {
        private(set) var written: [String] = []

        func snapshot() -> PasteboardSnapshot { PasteboardSnapshot(items: []) }
        func write(_ text: String) -> Int {
            written.append(text)
            return written.count
        }
        var changeCount: Int { written.count }
        func restore(_ snapshot: PasteboardSnapshot) {}
    }

    private final class FakeClock: MWSupport.Clock, @unchecked Sendable {
        let log: EventLog
        private(set) var slept: [Duration] = []

        init(log: EventLog) { self.log = log }

        var now: TimeInterval { 0 }
        func sleep(for duration: Duration) async throws {
            slept.append(duration)
            log.record("sleep")
        }
    }

    /// 1 September 2026, 17:38 local time — the mockup's own clock.
    private nonisolated static let reference: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 1
        components.hour = 17
        components.minute = 38
        return Calendar.current.date(from: components)!
    }()

    private struct Harness {
        let directory: URL
        let store: HistoryStore
        let log = EventLog()
        let paster: RecordingPaster
        let pasteboard = RecordingPasteboard()
        let clock: FakeClock
        let now: Date
        let retention: Int
        let running: Set<pid_t>

        init(retention: Int = 7, running: Set<pid_t> = [], now: Date = HistoryListModelTests.reference) {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mw-history-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.now = now
            self.retention = retention
            self.running = running
            store = HistoryStore(
                url: directory.appendingPathComponent("history.jsonl"),
                retention: { retention },
                now: { now }
            )
            paster = RecordingPaster(log: log)
            clock = FakeClock(log: log)
        }

        func add(_ entries: HistoryEntry...) async throws {
            for entry in entries { try await store.append(entry) }
        }

        @MainActor
        func model() -> HistoryListModel {
            HistoryListModel(deps: HistoryListModel.Dependencies(
                history: store,
                paster: paster,
                pasteboard: pasteboard,
                isRunning: { [running] pid in running.contains(pid) },
                retentionDays: { retention },
                clock: clock,
                now: { now },
                hide: { log.record("hide") },
                activate: { target in log.record("activate(\(target.pid))") }
            ))
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    private nonisolated static func entry(
        _ text: String,
        at date: Date,
        app: String = "Slack",
        bundleID: String? = "com.tinyspeck.slackmacgap",
        engine: String? = "speech_analyzer",
        seconds: Double = 6.2,
        cost: Double = 0.001
    ) -> HistoryEntry {
        HistoryEntry(
            timestamp: date,
            text: text,
            appName: app,
            bundleID: bundleID,
            engine: engine,
            streamedSeconds: seconds,
            costUSD: cost
        )
    }

    private nonisolated static func days(_ count: Int, before date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -count, to: date)!
    }

    // MARK: - Grouping and search

    @Test func groupsByDayNewestFirst() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let now = harness.now
        try await harness.add(
            Self.entry("earlier today", at: Self.days(0, before: now).addingTimeInterval(-3600)),
            Self.entry("just now", at: now),
            Self.entry("yesterday evening", at: Self.days(1, before: now)),
            Self.entry("three days ago", at: Self.days(3, before: now))
        )

        let model = harness.model()
        await model.reload()

        #expect(model.days.map(\.title).prefix(2) == ["Today", "Yesterday"])
        #expect(model.days.count == 3)
        #expect(model.days.first?.rows.map(\.text) == ["just now", "earlier today"])
        #expect(model.days.dropFirst().first?.rows.map(\.text) == ["yesterday evening"])
        #expect(model.days.last?.title != "Today")
        #expect(model.days.last?.title != "Yesterday")
    }

    @Test func searchFiltersCaseInsensitive() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.add(
            Self.entry("Move the design review to Thursday", at: harness.now),
            Self.entry("order the usual", at: harness.now.addingTimeInterval(-60))
        )

        let model = harness.model()
        model.query = "THURSDAY"
        await model.reload()

        #expect(model.days.flatMap(\.rows).map(\.text) == ["Move the design review to Thursday"])

        model.query = ""
        await model.reload()
        #expect(model.days.flatMap(\.rows).count == 2)
    }

    // MARK: - Row and footer text

    @Test func metaLineFormat() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.add(
            Self.entry("streamed", at: harness.now),
            Self.entry(
                "batch",
                at: harness.now.addingTimeInterval(-60),
                app: "Terminal",
                bundleID: "com.apple.Terminal",
                engine: "on_device",
                seconds: 0,
                cost: 0
            )
        )

        let model = harness.model()
        await model.reload()
        let rows = model.days.flatMap(\.rows)

        #expect(rows.first?.meta == "17:38 · Slack · SpeechAnalyzer · 6.2s · $0.001")
        #expect(rows.last?.meta == "17:37 · Terminal · On-device · $0.000")
    }

    /// Cleanup costs about $0.00004 a dictation; `$0.000` reads as free.
    @Test func metaMarksACostTooSmallToShow() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.add(Self.entry("cleaned up", at: harness.now, cost: 0.000042))

        let model = harness.model()
        await model.reload()

        #expect(model.days.flatMap(\.rows).first?.meta
            == "17:38 · Slack · SpeechAnalyzer · 6.2s · <$0.001")
    }

    @Test func footerText() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.add(
            Self.entry("one", at: harness.now),
            Self.entry("two", at: harness.now.addingTimeInterval(-60))
        )

        let model = harness.model()
        await model.reload()
        #expect(model.footer == "Keeping 7 days · 2 dictations")

        let single = Harness(retention: 1)
        defer { single.cleanUp() }
        try await single.add(Self.entry("only", at: single.now))
        let singleModel = single.model()
        await singleModel.reload()
        #expect(singleModel.footer == "Keeping 1 day · 1 dictation")
    }

    @Test func glyphLettersAndHashedColourStable() {
        #expect(AppGlyph(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap").letters == "S")
        #expect(AppGlyph(appName: "VS Code", bundleID: "com.microsoft.VSCode").letters == "VS")
        #expect(AppGlyph(appName: "Messages", bundleID: "com.apple.MobileSMS").letters == "M")
        #expect(AppGlyph(appName: "iterm", bundleID: nil).letters == "I")
        #expect(AppGlyph(appName: "", bundleID: nil).letters == "?")

        let first = AppGlyph(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        let second = AppGlyph(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        #expect(first == second)

        let samples = [
            AppGlyph(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
            AppGlyph(appName: "Terminal", bundleID: "com.apple.Terminal"),
            AppGlyph(appName: "VS Code", bundleID: "com.microsoft.VSCode"),
            AppGlyph(appName: "Safari", bundleID: "com.apple.Safari"),
            AppGlyph(appName: "Messages", bundleID: "com.apple.MobileSMS"),
        ]
        #expect(samples.allSatisfy { AppGlyph.palette.indices.contains($0.colorIndex) })
        #expect(Set(samples.map(\.colorIndex)).count > 1)
        // The colour follows the bundle ID, not the display name (design §5.4).
        #expect(
            AppGlyph(appName: "Slack", bundleID: "com.apple.Terminal").colorIndex
                == AppGlyph(appName: "Terminal", bundleID: "com.apple.Terminal").colorIndex
        )
    }

    // MARK: - Actions

    @Test func pasteEnabledOnlyWhenTargetRunning() async throws {
        let harness = Harness(running: [501])
        defer { harness.cleanUp() }
        let model = harness.model()

        #expect(model.pasteTitle == nil)
        #expect(model.canPaste == false)

        model.previousApp = PasteTarget(pid: 501, name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        #expect(model.pasteTitle == "Paste into Slack")
        #expect(model.canPaste)

        model.previousApp = PasteTarget(pid: 999, name: "TextEdit", bundleID: "com.apple.TextEdit")
        #expect(model.pasteTitle == "Paste into TextEdit")
        #expect(model.canPaste == false)
    }

    @Test func pasteUsesPreviousAppPidAndNoSubmit() async throws {
        let harness = Harness(running: [501])
        defer { harness.cleanUp() }
        try await harness.add(Self.entry("move the review", at: harness.now))

        let model = harness.model()
        model.previousApp = PasteTarget(pid: 501, name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        await model.reload()
        let row = try #require(model.days.first?.rows.first)

        await model.paste(row)

        #expect(harness.log.events == ["hide", "activate(501)", "sleep", "paste(501)"])
        #expect(harness.clock.slept == [.milliseconds(150)])
        let paste = try #require(harness.paster.pastes.first)
        #expect(paste.text == "move the review")
        #expect(paste.pid == 501)
        #expect(paste.submit == nil)
    }

    @Test func pasteDoesNothingWhenTheTargetIsGone() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.add(Self.entry("move the review", at: harness.now))

        let model = harness.model()
        model.previousApp = PasteTarget(pid: 501, name: "Slack", bundleID: nil)
        await model.reload()
        let row = try #require(model.days.first?.rows.first)

        await model.paste(row)

        #expect(harness.log.events.isEmpty)
        #expect(harness.paster.pastes.isEmpty)
    }

    @Test func copyWritesTheRowTextToThePasteboard() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.add(Self.entry("copy me", at: harness.now))

        let model = harness.model()
        await model.reload()
        let row = try #require(model.days.first?.rows.first)
        model.copy(row)

        #expect(harness.pasteboard.written == ["copy me"])
    }

    @Test func deleteRemovesTheEntryFromTheStore() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.add(
            Self.entry("keep", at: harness.now),
            Self.entry("drop", at: harness.now.addingTimeInterval(-60))
        )

        let model = harness.model()
        await model.reload()
        let row = try #require(model.days.first?.rows.last)
        await model.delete(row)

        #expect(model.days.flatMap(\.rows).map(\.text) == ["keep"])
        #expect(await harness.store.entries().map(\.text) == ["keep"])
    }

    @Test func clearRemovesEveryEntry() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.add(
            Self.entry("one", at: harness.now),
            Self.entry("two", at: harness.now.addingTimeInterval(-60))
        )

        let model = harness.model()
        await model.reload()
        await model.clear()

        #expect(model.days.isEmpty)
        #expect(model.footer == "Keeping 7 days · 0 dictations")
        #expect(await harness.store.entries().isEmpty)
    }
}
