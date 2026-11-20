import Darwin
import Foundation

/// Files holding voice data, owner-only (0600) from the instant they exist: `~/.config/mini-whisper`
/// is readable by others, so a file written at the umask's mode and chmodded after would be too,
/// for a moment.
enum PrivateFile {
    /// Opens `url` for writing, creating it 0600 when absent. `flags` adds `O_EXCL` or `O_APPEND`.
    static func open(_ url: URL, flags: Int32 = 0) throws -> FileHandle {
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_CLOEXEC | flags, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// Writes `data` to a new 0600 file in the same folder and renames it over `url`.
    static func replace(_ url: URL, with data: Data) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            let handle = try open(temp, flags: O_EXCL)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            guard rename(temp.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}
