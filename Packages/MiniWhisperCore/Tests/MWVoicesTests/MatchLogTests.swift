import Foundation
import MWConfig
import MWMeetings
import MWTestSupport
import Testing

import MWVoices

@Suite struct MatchLogTests {
    private let alice = UUID(uuidString: "0B6F7C1E-2D3A-4B5C-8D9E-0F1A2B3C4D5E")!
    private let bob = UUID(uuidString: "9A8B7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D")!
    private let carol = UUID(uuidString: "3C2B1A09-8F7E-4D6C-9B5A-4E3D2C1B0A9F")!
    private let meeting = UUID(uuidString: "7F3A9C2E-5B1D-4E0A-9C77-2D8F1A6B3C40")!
    private static let start = Date(timeIntervalSince1970: 1_795_168_800)  // 2026-11-20T10:00:00Z

    private func entry(_ event: MatchLog.Event, person: UUID?, second: Int = 0) -> MatchLog.Entry {
        MatchLog.Entry(
            at: Self.start.addingTimeInterval(Double(second)), meeting: meeting, key: "1:A", route: .local,
            event: event, person: person, score: 0.83, runnerUp: 0.31, seconds: 22
        )
    }

    private func lines(_ url: URL) throws -> [String] {
        String(decoding: try Data(contentsOf: url), as: UTF8.self).split(separator: "\n").map(String.init)
    }

    private func entries(_ url: URL) throws -> [MatchLog.Entry] {
        try lines(url).map { try MeetingCoding.decoder().decode(MatchLog.Entry.self, from: Data($0.utf8)) }
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    @Test func appendsOneJSONLinePerEntryAt0600() async throws {
        let temp = try TempDirectory()
        let url = temp.file("voice-matches.jsonl")
        let log = MatchLog(url: url)
        let appended = MatchLog.Event.allCases.enumerated().map { entry($0.element, person: alice, second: $0.offset) }

        for entry in appended { try await log.append(entry) }
        let speechmatics = MatchLog.Entry(
            at: Self.start, meeting: meeting, key: "1:S2", route: .speechmatics, event: .applied, person: bob,
            seconds: 88.5
        )
        try await log.append(speechmatics)

        #expect(MatchLog.Event.allCases.map(\.rawValue) == [
            "suggested", "applied", "accepted", "dismissed", "rejected", "renamed",
        ])
        #expect(try entries(url) == appended + [speechmatics])
        #expect(try lines(url).first == """
            {"at":"2026-11-20T10:00:00Z","event":"suggested","key":"1:A","meeting":"\(meeting.uuidString)",\
            "person":"\(alice.uuidString)","route":"local","runnerUp":0.31,"score":0.83,"seconds":22}
            """)
        #expect(try lines(url).last == """
            {"at":"2026-11-20T10:00:00Z","event":"applied","key":"1:S2","meeting":"\(meeting.uuidString)",\
            "person":"\(bob.uuidString)","route":"speechmatics","seconds":88.5}
            """)
        #expect(try Data(contentsOf: url).last == 0x0A)
        #expect(try permissions(url) == 0o600)
    }

    @Test func pastTheLimitTheOldestHalfIsDropped() async throws {
        let temp = try TempDirectory()
        let url = temp.file("voice-matches.jsonl")
        let log = MatchLog(url: url, limit: 1024)
        // Every line has the same length; only the time differs.
        let all = (0..<40).map { entry(.suggested, person: alice, second: $0) }

        try await log.append(all[0])
        let lineLength = try Data(contentsOf: url).count
        let fit = 1024 / lineLength
        for entry in all[1..<fit] { try await log.append(entry) }
        #expect(try entries(url) == Array(all[0..<fit]))

        try await log.append(all[fit])
        let count = fit + 1
        #expect(try entries(url) == Array(all[(count / 2)...fit]))
        #expect(try permissions(url) == 0o600)

        try await log.append(all[fit + 1])
        #expect(try entries(url) == Array(all[(count / 2)...(fit + 1)]))

        let exactURL = temp.file("exact.jsonl")
        let exact = MatchLog(url: exactURL, limit: 3 * lineLength)
        for entry in all[0..<3] { try await exact.append(entry) }
        #expect(try entries(exactURL) == Array(all[0..<3]))
        try await exact.append(all[3])
        #expect(try entries(exactURL) == Array(all[2..<4]))
    }

    @Test func removePeopleRewritesWithoutTheirLines() async throws {
        let temp = try TempDirectory()
        let url = temp.file("voice-matches.jsonl")
        let log = MatchLog(url: url)
        let appended = [
            entry(.suggested, person: alice, second: 0),
            entry(.applied, person: bob, second: 1),
            entry(.accepted, person: carol, second: 2),
            entry(.renamed, person: nil, second: 3),
            entry(.dismissed, person: alice, second: 4),
        ]
        for entry in appended { try await log.append(entry) }
        // An unreadable line may be theirs, so it goes with them.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"person\":\"not a uuid\"\n".utf8))
        try handle.close()

        try await log.remove(people: [alice, bob])

        #expect(try entries(url) == [appended[2], appended[3]])
        #expect(try permissions(url) == 0o600)
        let later = entry(.rejected, person: alice, second: 5)
        try await log.append(later)
        #expect(try entries(url) == [appended[2], appended[3], later])

        let unwritten = temp.file("unwritten.jsonl")
        try await MatchLog(url: unwritten).remove(people: [alice])
        #expect(exists(unwritten) == false)
    }

    @Test func removeAllDeletesTheFile() async throws {
        let temp = try TempDirectory()
        let url = temp.file("voice-matches.jsonl")
        let log = MatchLog(url: url)
        try await log.append(entry(.suggested, person: alice))

        try await log.removeAll()
        #expect(exists(url) == false)
        try await log.removeAll()

        try await log.append(entry(.applied, person: bob))
        #expect(try entries(url) == [entry(.applied, person: bob)])
        #expect(try permissions(url) == 0o600)
    }

    @Test func anUnwritableLogThrows() async throws {
        let temp = try TempDirectory()
        let folder = temp.file("config")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("voice-matches.jsonl")
        let log = MatchLog(url: url)
        try await log.append(entry(.suggested, person: alice))
        let fresh = MatchLog(url: folder.appendingPathComponent("other.jsonl"))

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }

        await #expect(throws: (any Error).self) { try await fresh.append(entry(.suggested, person: alice)) }
        await #expect(throws: (any Error).self) { try await log.remove(people: [alice]) }
        await #expect(throws: (any Error).self) { try await log.removeAll() }
        #expect(try entries(url) == [entry(.suggested, person: alice)])

        let blocked = temp.file("blocked.jsonl")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) { try await MatchLog(url: blocked).append(entry(.applied, person: bob)) }
    }
}
