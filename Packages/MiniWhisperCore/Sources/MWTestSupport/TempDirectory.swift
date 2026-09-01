import Foundation

/// A unique directory removed when the value goes out of scope.
public final class TempDirectory: @unchecked Sendable {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mw-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    public func file(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }
}
