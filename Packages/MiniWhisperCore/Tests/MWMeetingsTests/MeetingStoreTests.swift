import Foundation
import MWSupport
import MWTestSupport
import Testing

import MWMeetings

@Suite struct MeetingStoreTests {
    private struct Fixture {
        let temp: TempDirectory
        let root: URL
        let store: MeetingStore

        init() throws {
            temp = try TempDirectory()
            root = temp.file("meetings")
            store = MeetingStore(directory: root)
        }

        func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString) }
        var indexURL: URL { root.appendingPathComponent("index.json") }
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    private func contents(_ url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    private func segment(_ text: String, at start: Double, speaker: Int = 1) -> Segment {
        Segment(speaker: speaker, start: start, end: start + 1, text: text, session: 1, providerLabel: "S1")
    }

    @Test func createMakesA0700FolderAnd0600Files() async throws {
        let fixture = try Fixture()
        let meeting = MeetingFixtures.make().meeting

        try await fixture.store.create(meeting)

        let folder = fixture.folder(meeting.id)
        #expect(try permissions(fixture.root) == 0o700)
        #expect(try permissions(folder) == 0o700)
        #expect(try contents(folder) == ["meeting.json", "notes.jsonl", "segments.jsonl"])
        for name in try contents(folder) {
            #expect(try permissions(folder.appendingPathComponent(name)) == 0o600)
        }
        #expect(try permissions(fixture.indexURL) == 0o600)
    }

    @Test func appendedSegmentsAndNotesLoadInOrder() async throws {
        let fixture = try Fixture()
        let meeting = MeetingFixtures.make().meeting
        let segments = [segment("one", at: 1), segment("two", at: 2, speaker: 0), segment("three", at: 3)]
        let notes = [
            Note(time: 1.5, text: "first", createdAt: meeting.startedAt),
            Note(time: 2.5, text: "second\nline", createdAt: meeting.startedAt),
        ]

        try await fixture.store.create(meeting)
        for segment in segments { try await fixture.store.append(segment, to: meeting.id) }
        for note in notes { try await fixture.store.append(note, to: meeting.id) }

        let loaded = try fixture.store.load(meeting.id)
        #expect(loaded == LoadedMeeting(meeting: meeting, segments: segments, notes: notes))
    }

    @Test func updateRewritesMeetingJSONAndItsIndexEntry() async throws {
        let fixture = try Fixture()
        var meeting = MeetingFixtures.make().meeting
        try await fixture.store.create(meeting)

        meeting.title = "Renamed"
        meeting.endedAt = meeting.startedAt.addingTimeInterval(600)
        meeting.durationSeconds = 590
        meeting.billing = Billing(engineSeconds: 590, costUSD: 0.07375)
        try await fixture.store.update(meeting)

        #expect(try fixture.store.load(meeting.id).meeting == meeting)
        let entry = try #require(try fixture.store.index().first)
        #expect(entry.id == meeting.id)
        #expect(entry.title == "Renamed")
        #expect(entry.endedAt == meeting.endedAt)
        #expect(entry.duration == 590)
        #expect(entry.costUSD == 0.07375)
        #expect(entry.hasSummary == false)
        #expect(try fixture.store.index().count == 1)
    }

    @Test func indexExcerptIsTheSummaryOpeningOrTheFirstSegment() async throws {
        let fixture = try Fixture()
        let plain = MeetingFixtures.make().meeting
        try await fixture.store.create(plain)
        try await fixture.store.append(segment("Morning everyone, let's start.", at: 4), to: plain.id)
        try await fixture.store.append(segment("Second thought.", at: 9), to: plain.id)
        try await fixture.store.update(plain)

        let northwind = MeetingFixtures.northwind()
        try await fixture.store.create(northwind.meeting)
        try await fixture.store.update(northwind.meeting)

        let entries = try fixture.store.index()
        let plainEntry = try #require(entries.first { $0.id == plain.id })
        #expect(plainEntry.excerpt == "Morning everyone, let's start.")
        #expect(plainEntry.hasSummary == false)
        let northwindEntry = try #require(entries.first { $0.id == northwind.meeting.id })
        #expect(northwindEntry.excerpt == """
            The Northwind rollout stays on schedule provided the migration script is reviewed by \
            Wednesday, after Priya refreshes staging data tonight.
            """)
        #expect(northwindEntry.hasSummary)
        #expect(northwindEntry.speakerCount == 3)
        #expect(abs(northwindEntry.costUSD - 0.39756) < 1e-9)
        #expect(entries.map(\.id) == [northwind.meeting.id, plain.id])
    }

    @Test func rewriteSegmentsReplacesAtomically() async throws {
        let fixture = try Fixture()
        let meeting = MeetingFixtures.make().meeting
        try await fixture.store.create(meeting)
        try await fixture.store.append(segment("one", at: 1), to: meeting.id)
        try await fixture.store.append(segment("two", at: 2), to: meeting.id)

        var edited = segment("one, edited", at: 1)
        edited.edited = true
        try await fixture.store.rewriteSegments([edited], of: meeting.id)
        let later = segment("three", at: 3)
        try await fixture.store.append(later, to: meeting.id)

        #expect(try fixture.store.load(meeting.id).segments == [edited, later])
        #expect(try contents(fixture.folder(meeting.id)) == ["meeting.json", "notes.jsonl", "segments.jsonl"])
        #expect(try contents(fixture.root) == [meeting.id.uuidString, "index.json"].sorted())
        #expect(try permissions(fixture.folder(meeting.id).appendingPathComponent("segments.jsonl")) == 0o600)
    }

    @Test func corruptSegmentLineIsSkippedAndLogged() async throws {
        let fixture = try Fixture()
        let meeting = MeetingFixtures.make().meeting
        try await fixture.store.create(meeting)
        let corrupt = try #require(
            Bundle.module.url(forResource: "corrupt-segments", withExtension: "jsonl", subdirectory: "Fixtures")
        )
        let segments = fixture.folder(meeting.id).appendingPathComponent("segments.jsonl")
        try FileManager.default.removeItem(at: segments)
        try FileManager.default.copyItem(at: corrupt, to: segments)

        let sink = CapturingLogSink()
        let loaded = try await Log.withSinks(debug: false, sinks: [sink]) {
            try fixture.store.load(meeting.id)
        }

        #expect(loaded.segments.map(\.text) == ["First line.", "Third line."])
        #expect(sink.lines.contains { $0.contains("skipped 1") })
    }

    @Test func missingIndexIsRebuiltAndPersistedByTheActor() async throws {
        let fixture = try Fixture()
        let first = MeetingFixtures.make().meeting
        let second = MeetingFixtures.northwind().meeting
        try await fixture.store.create(first)
        try await fixture.store.create(second)
        try FileManager.default.removeItem(at: fixture.indexURL)

        let entries = try await fixture.store.refreshIndex()

        #expect(Set(entries.map(\.id)) == [first.id, second.id])
        #expect(try permissions(fixture.indexURL) == 0o600)
        let stored = try MeetingCoding.decoder().decode([IndexEntry].self, from: Data(contentsOf: fixture.indexURL))
        #expect(stored == entries)
    }

    @Test func indexIsMissingOnlyBesideStoredMeetings() async throws {
        let fixture = try Fixture()
        #expect(fixture.store.isIndexMissing == false)

        try await fixture.store.create(MeetingFixtures.make().meeting)
        #expect(fixture.store.isIndexMissing == false)

        try FileManager.default.removeItem(at: fixture.indexURL)
        #expect(fixture.store.isIndexMissing)
        try await fixture.store.refreshIndex()
        #expect(fixture.store.isIndexMissing == false)
    }

    @Test func readerRebuildsInMemoryWithoutWriting() async throws {
        let fixture = try Fixture()
        let meeting = MeetingFixtures.make().meeting
        try await fixture.store.create(meeting)
        try FileManager.default.removeItem(at: fixture.indexURL)

        let reader: any MeetingReading = MeetingStore(directory: fixture.root)
        let entries = try reader.index()

        #expect(entries.map(\.id) == [meeting.id])
        #expect(FileManager.default.fileExists(atPath: fixture.indexURL.path) == false)
    }

    @Test func readerSeesCompleteFilesWhileTheActorWrites() async throws {
        let fixture = try Fixture()
        let meeting = MeetingFixtures.northwind().meeting
        try await fixture.store.create(meeting)
        let reader: any MeetingReading = MeetingStore(directory: fixture.root)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for revision in 0..<100 {
                    var renamed = meeting
                    renamed.title = "Revision \(revision)"
                    try await fixture.store.update(renamed)
                }
            }
            group.addTask {
                for _ in 0..<300 {
                    let loaded = try reader.load(meeting.id)
                    let entries = try reader.index()
                    #expect(loaded.meeting.id == meeting.id)
                    #expect(entries.map(\.id) == [meeting.id])
                }
            }
            try await group.waitForAll()
        }
    }

    @Test func deleteRemovesTheFolderAndItsIndexEntry() async throws {
        let fixture = try Fixture()
        let kept = MeetingFixtures.make().meeting
        let deleted = MeetingFixtures.northwind().meeting
        try await fixture.store.create(kept)
        try await fixture.store.create(deleted)
        try await fixture.store.append(segment("gone", at: 1), to: deleted.id)

        try await fixture.store.delete(deleted.id)

        #expect(FileManager.default.fileExists(atPath: fixture.folder(deleted.id).path) == false)
        #expect(try fixture.store.index().map(\.id) == [kept.id])
    }

    @Test func deleteAudioRemovesTheFileAndZeroesAudioBytes() async throws {
        let fixture = try Fixture()
        let meeting = MeetingFixtures.make().meeting
        try await fixture.store.create(meeting)
        let audio = fixture.store.audioURL(meeting.id)
        try Data(count: 1000).write(to: audio)
        try await fixture.store.update(meeting)
        #expect(try fixture.store.index().first?.audioBytes == 1000)

        try await fixture.store.deleteAudio(meeting.id)

        #expect(FileManager.default.fileExists(atPath: audio.path) == false)
        #expect(try fixture.store.index().first?.audioBytes == 0)
    }

    private let tag = TestCallTag(scenarioID: "sprint-planning", revision: 1, scenarioTitle: "Sprint planning")

    private func record() -> TestCallRecord {
        TestCallRecord(
            scenario: .init(id: "sprint-planning", revision: 1, title: "Sprint planning"),
            engine: .assemblyaiStreaming,
            overlap: true,
            scoredAt: Date(timeIntervalSince1970: 1_794_395_762),
            voices: [.init(role: .a, character: "Tom", requested: "Daniel", voice: "Daniel")],
            lines: [
                .init(index: 0, role: .a, status: .done, start: 1, end: 3, overlapped: false, reference: "Morning all.",
                      counts: .init(words: 2, substitutions: 0, deletions: 0, insertions: 0),
                      heard: [.init(text: "Morning", op: .match), .init(text: "all", op: .match)],
                      labels: ["1": 2], segmentStart: 1.1, latency: 0.8),
                .init(index: 1, role: .you, status: .notReached, reference: "Thanks."),
            ],
            roles: [.init(role: .a, words: 2, substitutions: 0, deletions: 0, insertions: 0,
                          majorityLabel: 1, majorityLabelName: "Speaker 1", purity: 1)],
            overall: .init(words: 2, substitutions: 0, deletions: 0, insertions: 0),
            crossCredited: .init(voiceWordsAsYou: 0, yourWordsAsVoices: 0),
            latency: .init(median: 0.8, max: 0.8, maxLine: 0)
        )
    }

    @Test func testCallRoundTripsAs0600() async throws {
        let fixture = try Fixture()
        let meeting = MeetingFixtures.make(test: tag).meeting
        try await fixture.store.create(meeting)

        try await fixture.store.writeTestCall(record(), of: meeting.id)

        #expect(try fixture.store.readTestCall(meeting.id) == record())
        #expect(try permissions(fixture.folder(meeting.id).appendingPathComponent("testcall.json")) == 0o600)
        #expect(try contents(fixture.folder(meeting.id)) == [
            "meeting.json", "notes.jsonl", "segments.jsonl", "testcall.json",
        ])
    }

    @Test func absentTestCallReadsNil() async throws {
        let fixture = try Fixture()
        let meeting = MeetingFixtures.make(test: tag).meeting
        try await fixture.store.create(meeting)

        #expect(try fixture.store.readTestCall(meeting.id) == nil)
        #expect(try fixture.store.readTestCall(UUID()) == nil)
    }

    @Test func undecodableTestCallThrows() async throws {
        let fixture = try Fixture()
        let meeting = MeetingFixtures.make(test: tag).meeting
        try await fixture.store.create(meeting)
        try Data("not json".utf8).write(to: fixture.folder(meeting.id).appendingPathComponent("testcall.json"))

        #expect(throws: (any Error).self) { try fixture.store.readTestCall(meeting.id) }
    }

    @Test func indexRowCarriesTheTag() async throws {
        let fixture = try Fixture()
        var meeting = MeetingFixtures.make(test: tag).meeting
        try await fixture.store.create(meeting)
        #expect(try fixture.store.index().first?.test == tag)

        meeting.test?.wer = 0.064
        try await fixture.store.update(meeting)

        let entry = try #require(try fixture.store.index().first)
        #expect(entry.test?.wer == 0.064)
        #expect(entry.test?.scenarioID == "sprint-planning")
    }

    @Test func rescanRebuildsTheTag() async throws {
        let fixture = try Fixture()
        var meeting = MeetingFixtures.make(test: tag).meeting
        meeting.test?.wer = 0.064
        try await fixture.store.create(meeting)
        try await fixture.store.create(MeetingFixtures.northwind().meeting)
        try FileManager.default.removeItem(at: fixture.indexURL)

        let entries = try fixture.store.index()

        #expect(entries.first { $0.id == meeting.id }?.test == meeting.test)
        #expect(entries.first { $0.id == MeetingFixtures.northwindID }?.test == nil)
    }

    @Test func audioURLIsInsideTheMeetingFolder() throws {
        let fixture = try Fixture()
        let id = UUID()

        #expect(fixture.store.audioURL(id) == fixture.folder(id).appendingPathComponent("audio.m4a"))
    }
}
