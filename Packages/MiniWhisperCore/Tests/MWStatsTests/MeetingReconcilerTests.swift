import Foundation
import Testing

import MWMeetings
import MWStats
import MWSupport
import MWTestSupport

@Suite struct MeetingReconcilerTests {
    private static let newYork = TimeZone(identifier: "America/New_York")!
    private static let now = Date(timeIntervalSince1970: 1_795_540_278)  // 2026-11-24T17:11:18Z
    private static let nowText = "2026-11-24T17:11:18+00:00"

    /// Stored meetings in memory. Counts index reads and loads, serves the `modified` dates the
    /// test sets, and while held keeps every load waiting until `release()`.
    private final class SpySource: MeetingSource, @unchecked Sendable {
        private struct Failure: Error {}

        private let condition = NSCondition()
        private let meetings: [LoadedMeeting]
        private let dates: [UUID: Date]
        private let failing: Set<UUID>
        private var held = false
        private var loaded: [UUID] = []
        private var indexed = 0
        private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

        init(_ meetings: [LoadedMeeting], modified: [UUID: Date] = [:], failing: Set<UUID> = []) {
            self.meetings = meetings
            dates = modified
            self.failing = failing
        }

        var loads: [UUID] { condition.withLock { loaded } }
        var indexReads: Int { condition.withLock { indexed } }

        func hold() {
            condition.withLock { held = true }
        }

        func release() {
            condition.withLock {
                held = false
                condition.broadcast()
            }
        }

        /// Returns once `load` has been entered `count` times.
        func waitUntilLoading(_ count: Int) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let reached = condition.withLock {
                    if loaded.count < count { waiters.append((count, continuation)) }
                    return loaded.count >= count
                }
                if reached { continuation.resume() }
            }
        }

        func index() throws -> [IndexEntry] {
            condition.withLock { indexed += 1 }
            return meetings.map { loaded in
                let meeting = loaded.meeting
                return IndexEntry(
                    id: meeting.id, title: meeting.title, startedAt: meeting.startedAt, endedAt: meeting.endedAt,
                    duration: meeting.durationSeconds, mode: meeting.mode, app: meeting.app,
                    engine: meeting.engine, speakerCount: meeting.speakers.count, costUSD: meeting.totalCostUSD,
                    hasSummary: meeting.summary != nil, audioBytes: 0, excerpt: "", test: meeting.test
                )
            }
        }

        func load(_ id: UUID) throws -> LoadedMeeting {
            let ready = condition.withLock {
                loaded.append(id)
                let ready = waiters.filter { $0.count <= loaded.count }
                waiters.removeAll { $0.count <= loaded.count }
                return ready
            }
            ready.forEach { $0.continuation.resume() }
            condition.lock()
            while held { condition.wait() }
            condition.unlock()
            guard !failing.contains(id), let meeting = meetings.first(where: { $0.meeting.id == id }) else {
                throw Failure()
            }
            return meeting
        }

        func meeting(_ id: UUID) throws -> Meeting {
            guard let loaded = meetings.first(where: { $0.meeting.id == id }) else { throw Failure() }
            return loaded.meeting
        }

        func modified(_ id: UUID) -> Date? {
            dates[id]
        }
    }

    /// A finished ten-minute meeting with one segment.
    private func ended(
        id: UUID = UUID(), test: TestCallTag? = nil, finished: Bool = true
    ) -> LoadedMeeting {
        var loaded = MeetingFixtures.make(
            id: id,
            segments: [Segment(speaker: 0, start: 1, end: 4, text: "Hello there.", session: 1)],
            test: test
        )
        if finished {
            loaded.meeting.endedAt = loaded.meeting.startedAt.addingTimeInterval(600)
            loaded.meeting.durationSeconds = 600
        }
        return loaded
    }

    private func figures(_ loaded: LoadedMeeting, at now: Date = MeetingReconcilerTests.now) -> MeetingRow {
        MeetingFigures.compute(loaded, fallback: Self.newYork, now: now)
    }

    private func stats(_ temp: TempDirectory) async -> StatsStore {
        let stats = StatsStore(directory: temp.file("stats"), now: { Self.now })
        await stats.open()
        return stats
    }

    private func reconciler(
        _ stats: StatsStore, _ source: any MeetingSource, now: Date = MeetingReconcilerTests.now
    ) -> MeetingReconciler {
        MeetingReconciler(stats: stats, source: source, timeZone: { Self.newYork }, now: { now })
    }

    private static func date(_ text: String) throws -> Date {
        try #require(StatsTime.parse(text)).date
    }

    // MARK: - Which meetings are computed

    @Test func aMissingRowIsComputed() async throws {
        let temp = try TempDirectory()
        let stats = await stats(temp)
        let meeting = ended()
        let source = SpySource([meeting])

        let changed = await reconciler(stats, source).reconcile()

        #expect(changed)
        #expect(await stats.meetingRows() == [meeting.meeting.id: figures(meeting)])
        #expect(source.loads == [meeting.meeting.id])
    }

    /// A row of an earlier figures version, one computed before its files last changed, and one
    /// whose computed time cannot be read.
    @Test(arguments: [
        (0, "2026-11-24T17:00:00+00:00", "2026-11-24T16:00:00+00:00"),
        (1, "2026-11-24T17:00:00+00:00", "2026-11-24T17:00:01+00:00"),
        (1, "", "2026-11-24T16:00:00+00:00"),
    ])
    func aStaleRowIsComputed(figures version: Int, computed: String, modified: String) async throws {
        let temp = try TempDirectory()
        let stats = await stats(temp)
        let meeting = ended()
        await stats.upsert(MeetingRow(id: meeting.meeting.id, words: 999, figures: version, computed: computed))
        let source = SpySource([meeting], modified: [meeting.meeting.id: try Self.date(modified)])

        let changed = await reconciler(stats, source).reconcile()

        #expect(changed)
        #expect(await stats.meetingRows()[meeting.meeting.id] == figures(meeting))
    }

    /// The row's computed time is whole seconds, so files changed within that second are not newer.
    @Test func aFreshRowIsNotLoadedAndNothingChanges() async throws {
        let temp = try TempDirectory()
        let stats = await stats(temp)
        let earlier = ended(), sameSecond = ended(), noDate = ended()
        for meeting in [earlier, sameSecond, noDate] {
            await stats.upsert(
                MeetingRow(id: meeting.meeting.id, figures: MeetingFigures.version, computed: "2026-11-24T17:00:00+00:00")
            )
        }
        let source = SpySource([earlier, sameSecond, noDate], modified: [
            earlier.meeting.id: try Self.date("2026-11-24T16:59:59+00:00"),
            sameSecond.meeting.id: try Self.date("2026-11-24T17:00:00+00:00").addingTimeInterval(0.75),
        ])

        let changed = await reconciler(stats, source).reconcile()

        #expect(!changed)
        #expect(source.loads.isEmpty)
    }

    @Test func testCallsAndUnfinishedMeetingsAreSkipped() async throws {
        let temp = try TempDirectory()
        let stats = await stats(temp)
        let tag = TestCallTag(scenarioID: "standup", revision: 1, scenarioTitle: "Stand-up")
        let source = SpySource([ended(test: tag), ended(finished: false)])

        let changed = await reconciler(stats, source).reconcile()

        #expect(!changed)
        #expect(source.loads.isEmpty)
        #expect(await stats.meetingRows().isEmpty)
    }

    @Test func aMeetingThatCannotBeLoadedIsSkippedAndThePassContinues() async throws {
        let temp = try TempDirectory()
        let stats = await stats(temp)
        let broken = ended(), fine = ended()
        let source = SpySource([broken, fine], failing: [broken.meeting.id])
        let sink = CapturingLogSink()

        let changed = await Log.withSinks(debug: false, sinks: [sink]) {
            await reconciler(stats, source).reconcile()
        }

        #expect(changed)
        #expect(await stats.meetingRows() == [fine.meeting.id: figures(fine)])
        let warning = "WARNING stats meeting \(broken.meeting.id.uuidString) not reconciled: "
        #expect(sink.lines.filter { $0.hasPrefix(warning) }.count == 1)
    }

    // MARK: - One pass at a time

    /// The second call is made while the first pass waits in `load`; the release can only run once
    /// this test's task has left the main actor for the reconciler.
    @MainActor @Test func concurrentCallsShareOnePass() async throws {
        let temp = try TempDirectory()
        let stats = await stats(temp)
        let first = ended(), second = ended()
        let source = SpySource([first, second])
        let reconciler = reconciler(stats, source)
        source.hold()

        let running = Task { await reconciler.reconcile() }
        await source.waitUntilLoading(1)
        Task { source.release() }
        let joined = await reconciler.reconcile()

        #expect(await running.value)
        #expect(joined)
        #expect(source.indexReads == 1)
        #expect(source.loads.sorted { $0.uuidString < $1.uuidString }
            == [first.meeting.id, second.meeting.id].sorted { $0.uuidString < $1.uuidString })
    }

    @Test func progressCountsEachMeetingThenGoesIdle() async throws {
        let temp = try TempDirectory()
        let stats = await stats(temp)
        let reconciler = reconciler(stats, SpySource([ended(), ended(), ended()]))

        await reconciler.reconcile()

        var progress = reconciler.progress.makeAsyncIterator()
        var seen: [ReconcileProgress?] = []
        for _ in 0..<4 { seen.append(try #require(await progress.next())) }
        #expect(seen == [
            ReconcileProgress(done: 1, total: 3), ReconcileProgress(done: 2, total: 3),
            ReconcileProgress(done: 3, total: 3), nil,
        ])
    }

    @Test func aPassLogsItsCounts() async throws {
        let temp = try TempDirectory()
        let stats = await stats(temp)
        let fresh = ended()
        await stats.upsert(MeetingRow(id: fresh.meeting.id, figures: MeetingFigures.version, computed: Self.nowText))
        let source = SpySource([ended(), fresh, ended()])
        let sink = CapturingLogSink()

        _ = await Log.withSinks(debug: false, sinks: [sink]) {
            await reconciler(stats, source).reconcile()
        }

        let pattern = /INFO stats reconcile, 2 computed, 0 word entries, 0 removed, \d+ ms/
        #expect(sink.lines.filter { $0.wholeMatch(of: pattern) != nil }.count == 1)
    }

    // MARK: - A meeting stops

    /// The pass reads `first` and `last`; `stopped` has a fresh row, so only `meetingStopped` reads
    /// it, and only after the pass.
    @MainActor @Test func meetingStoppedWaitsForARunningPassThenUpsertsThatMeetingAlone() async throws {
        let temp = try TempDirectory()
        let stats = await stats(temp)
        let first = ended(), stopped = ended(), last = ended()
        await stats.upsert(
            MeetingRow(id: stopped.meeting.id, words: 999, figures: MeetingFigures.version, computed: Self.nowText)
        )
        let source = SpySource([first, stopped, last])
        let reconciler = reconciler(stats, source)
        source.hold()

        let pass = Task { await reconciler.reconcile() }
        await source.waitUntilLoading(1)
        Task { source.release() }
        await reconciler.meetingStopped(stopped.meeting.id)

        #expect(await pass.value)
        #expect(source.loads == [first.meeting.id, last.meeting.id, stopped.meeting.id])
        #expect(await stats.meetingRows()[stopped.meeting.id] == figures(stopped))
    }

    @Test func meetingStoppedSkipsATestCallAndAnUnfinishedMeeting() async throws {
        let temp = try TempDirectory()
        let stats = await stats(temp)
        let tag = TestCallTag(scenarioID: "standup", revision: 1, scenarioTitle: "Stand-up")
        let testCall = ended(test: tag), unfinished = ended(finished: false), kept = ended()
        let reconciler = reconciler(stats, SpySource([testCall, unfinished, kept]))

        for meeting in [testCall, unfinished, kept] { await reconciler.meetingStopped(meeting.meeting.id) }

        #expect(await stats.meetingRows() == [kept.meeting.id: figures(kept)])
    }

    // MARK: - Through a real store

    @Test func keptMeetingsAreEndedAndNotTests() async throws {
        let temp = try TempDirectory()
        let store = MeetingStore(directory: temp.file("meetings"))
        let tag = TestCallTag(scenarioID: "standup", revision: 1, scenarioTitle: "Stand-up")
        let kept = ended()
        for loaded in [kept, ended(test: tag), ended(finished: false)] {
            try await store.create(loaded.meeting)
        }

        #expect(try store.keptMeetings().map(\.id) == [kept.meeting.id])
    }

    /// No transcript, note, title or name reaches `stats/`, and a second pass over unchanged
    /// files reads nothing.
    @Test func northwindThroughARealStoreLeavesNoTextInStats() async throws {
        let temp = try TempDirectory()
        let store = MeetingStore(directory: temp.file("meetings"))
        let northwind = MeetingFixtures.northwind()
        try await store.create(northwind.meeting)
        for segment in northwind.segments { try await store.append(segment, to: northwind.meeting.id) }
        for note in northwind.notes { try await store.append(note, to: northwind.meeting.id) }
        let stats = await stats(temp)
        // Later than the files' real modification times.
        let reconciler = reconciler(stats, store, now: Date(timeIntervalSince1970: 1_900_000_000))

        #expect(await reconciler.reconcile())
        #expect(!(await reconciler.reconcile()))

        let folder = temp.file("stats")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == ["meetings.jsonl"])
        let bytes = try names.map { try String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8) }
            .joined()
        #expect(bytes.contains(northwind.meeting.id.uuidString))
        let meeting = northwind.meeting
        let texts = northwind.segments.map(\.text) + northwind.notes.map(\.text)
            + [meeting.title, meeting.userName] + meeting.speakers.map(\.name)
            + ["Northwind", "Marta", "Priya", "Alex"]
        for text in texts {
            #expect(!bytes.contains(text), "\(text)")
        }
    }
}
