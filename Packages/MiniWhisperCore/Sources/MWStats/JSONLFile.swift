import Foundation
import MWSupport

/// One JSON value per line, sorted keys, owner-only in an owner-only folder. A line that cannot
/// be decoded, such as one a crash cut short, is skipped and counted rather than failing the read.
public struct JSONLFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// A last line without its newline gets one first, so a torn line never joins the next.
    public func append(_ value: some Encodable) throws {
        var line = try Self.encoder().encode(value)
        line.append(0x0A)
        if try lacksFinalNewline() { line.insert(0x0A, at: 0) }
        try Self.makeFolder(for: url)
        let handle = try PrivateFile.open(url, flags: O_APPEND)
        defer { try? handle.close() }
        try handle.write(contentsOf: line)
    }

    /// Empty when the file is absent.
    public func read<Value: Decodable>(_ type: Value.Type) throws -> (values: [Value], skipped: Int) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return ([], 0)
        }
        let decoder = JSONDecoder()
        var values: [Value] = []
        var skipped = 0
        for line in data.split(separator: 0x0A) {
            if let value = try? decoder.decode(Value.self, from: Data(line)) {
                values.append(value)
            } else {
                skipped += 1
            }
        }
        if skipped > 0 { Log.stats.warning("\(url.lastPathComponent): skipped \(skipped) unreadable line(s)") }
        return (values, skipped)
    }

    public func rewrite<Value: Encodable>(_ values: [Value]) throws {
        let encoder = Self.encoder()
        var data = Data()
        for value in values {
            data.append(try encoder.encode(value))
            data.append(0x0A)
        }
        try Self.makeFolder(for: url)
        try PrivateFile.replace(url, with: data)
    }

    /// One JSON document, for the single-document files beside the line files.
    public static func writeAtomically(_ value: some Encodable, to url: URL) throws {
        let data = try encoder().encode(value)
        try makeFolder(for: url)
        try PrivateFile.replace(url, with: data)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeFolder(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func lacksFinalNewline() throws -> Bool {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size > 0 else { return false }
        try handle.seek(toOffset: size - 1)
        return try handle.read(upToCount: 1) != Data([0x0A])
    }
}
