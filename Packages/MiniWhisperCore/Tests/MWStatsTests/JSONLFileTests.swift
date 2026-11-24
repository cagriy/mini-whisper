import Foundation
import MWSupport
import MWTestSupport
import Testing

import MWStats

@Suite struct JSONLFileTests {
    private struct Day: Codable, Equatable {
        var day: String
        var words: Int?
    }

    private func mode(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    private func inode(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int)
    }

    private func copyTornFixture(to url: URL) throws {
        let fixture = try #require(
            Bundle.module.url(forResource: "torn-days", withExtension: "jsonl", subdirectory: "Fixtures")
        )
        try FileManager.default.copyItem(at: fixture, to: url)
    }

    @Test func appendCreatesAnOwnerOnlyFileInAnOwnerOnlyFolder() throws {
        let temp = try TempDirectory()
        let folder = temp.file("stats")
        let file = JSONLFile(url: folder.appendingPathComponent("days.jsonl"))

        try file.append(Day(day: "2026-11-30", words: 4))

        #expect(try mode(of: folder) == 0o700)
        #expect(try mode(of: file.url) == 0o600)
        #expect(try String(contentsOf: file.url, encoding: .utf8) == "{\"day\":\"2026-11-30\",\"words\":4}\n")
    }

    @Test func appendAfterALastLineWithoutItsNewlineKeepsThatLineWhole() throws {
        let temp = try TempDirectory()
        let url = temp.file("days.jsonl")
        try Data(#"{"day":"2026-11-29","words":2}"#.utf8).write(to: url)
        let file = JSONLFile(url: url)

        try file.append(Day(day: "2026-11-30", words: 4))

        let read = try file.read(Day.self)
        #expect(read.values == [Day(day: "2026-11-29", words: 2), Day(day: "2026-11-30", words: 4)])
        #expect(read.skipped == 0)
    }

    @Test func aTornLineNeverJoinsTheNextAppend() throws {
        let temp = try TempDirectory()
        let url = temp.file("days.jsonl")
        try copyTornFixture(to: url)
        let file = JSONLFile(url: url)

        try file.append(Day(day: "2026-11-30", words: 4))

        let read = try file.read(Day.self)
        #expect(read.values.last == Day(day: "2026-11-30", words: 4))
        #expect(read.values.count == 3)
        #expect(read.skipped == 1)
    }

    @Test func readSkipsATornLineAndLogsItsCountWithTheFileNameOnly() async throws {
        let temp = try TempDirectory()
        let url = temp.file("torn-days.jsonl")
        try copyTornFixture(to: url)
        let sink = CapturingLogSink()

        let read = try await Log.withSinks(debug: false, sinks: [sink]) {
            try JSONLFile(url: url).read(Day.self)
        }

        #expect(read.values == [Day(day: "2026-11-01", words: 120), Day(day: "2026-11-02", words: 40)])
        #expect(read.skipped == 1)
        #expect(sink.lines == ["WARNING stats torn-days.jsonl: skipped 1 unreadable line(s)"])
    }

    @Test func readOfAMissingFileIsEmpty() throws {
        let temp = try TempDirectory()

        let read = try JSONLFile(url: temp.file("days.jsonl")).read(Day.self)

        #expect(read.values.isEmpty)
        #expect(read.skipped == 0)
    }

    @Test func rewriteReplacesTheFileByRenameAt0600() throws {
        let temp = try TempDirectory()
        let url = temp.file("days.jsonl")
        let file = JSONLFile(url: url)
        try file.append(Day(day: "2026-11-29", words: 2))
        try file.append(Day(day: "2026-11-29", words: 3))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let before = try inode(of: url)

        try file.rewrite([Day(day: "2026-11-29", words: 5)])

        #expect(try file.read(Day.self).values == [Day(day: "2026-11-29", words: 5)])
        #expect(try mode(of: url) == 0o600)
        #expect(try inode(of: url) != before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.url.path) == ["days.jsonl"])
    }

    @Test func writeAtomicallyWritesOneSortedDocumentAt0600() throws {
        let temp = try TempDirectory()
        let url = temp.file("meta.json")
        try Data("old".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        try JSONLFile.writeAtomically(Day(day: "2026-11-30", words: 1), to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == #"{"day":"2026-11-30","words":1}"#)
        #expect(try mode(of: url) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.url.path) == ["meta.json"])
    }
}
