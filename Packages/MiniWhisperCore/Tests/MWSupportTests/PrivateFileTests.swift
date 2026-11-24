import Foundation
import MWSupport
import MWTestSupport
import Testing

/// Voice data and statistics are owner-only from the instant a file exists, not chmodded after a
/// write the umask left readable by others.
@Suite struct PrivateFileTests {
    private func mode(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    @Test func aNewFileIsOwnerOnlyBeforeAnythingIsWritten() throws {
        let directory = try TempDirectory()
        let url = directory.file("voices.json")

        let handle = try PrivateFile.open(url, flags: O_EXCL)
        defer { try? handle.close() }

        #expect(try mode(of: url) == 0o600)
    }

    @Test func anExclusiveOpenOfAnExistingFileFails() throws {
        let directory = try TempDirectory()
        let url = directory.file("voices.json")
        try Data("x".utf8).write(to: url)

        #expect(throws: POSIXError.self) { try PrivateFile.open(url, flags: O_EXCL) }
    }

    @Test func replaceWritesTheBytesAt0600AndLeavesNoTempFile() throws {
        let directory = try TempDirectory()
        let url = directory.file("voices.json")
        try Data("old".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        try PrivateFile.replace(url, with: Data("new".utf8))

        #expect(try Data(contentsOf: url) == Data("new".utf8))
        #expect(try mode(of: url) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == ["voices.json"])
    }

    @Test func aFailedReplaceLeavesTheTargetAndNoTempFile() throws {
        let directory = try TempDirectory()
        let url = directory.file("voices.json")
        try FileManager.default.createDirectory(at: url.appendingPathComponent("blocker"), withIntermediateDirectories: true)

        #expect(throws: (any Error).self) { try PrivateFile.replace(url, with: Data("new".utf8)) }

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == ["voices.json"])
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("blocker").path))
    }
}
