import Foundation
import os

public enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

public struct LogRecord: Sendable, Equatable {
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String
}

public protocol LogSink: Sendable {
    func write(_ record: LogRecord)
}

public struct LogCategory: Sendable {
    public let name: String
    private let logger: Logger

    init(name: String) {
        self.name = name
        self.logger = Logger(subsystem: Log.subsystem, category: name)
    }

    public func debug(_ message: @autoclosure () -> String) { emit(.debug, message) }
    public func info(_ message: @autoclosure () -> String) { emit(.info, message) }
    public func warning(_ message: @autoclosure () -> String) { emit(.warning, message) }
    public func error(_ message: @autoclosure () -> String) { emit(.error, message) }

    private func emit(_ level: LogLevel, _ message: () -> String) {
        let state = Log.state
        guard level != .debug || state.debug else { return }
        let text = message()
        // Messages are composed by call sites that never include keys, transcripts or
        // prompt bodies above DEBUG (design §5.8), so they are safe to log publicly.
        switch level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .warning: logger.warning("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        }
        guard !state.sinks.isEmpty else { return }
        let record = LogRecord(timestamp: Date(), level: level, category: name, message: text)
        for sink in state.sinks { sink.write(record) }
    }
}

/// Unified-logging facade with an optional sink list (design §5.11, F38).
public enum Log {
    public static let subsystem = "com.ips.mini-whisper"

    struct State: Sendable {
        var debug = false
        var sinks: [any LogSink] = []
    }

    private static let storage = OSAllocatedUnfairLock(initialState: State())

    static var state: State { storage.withLock { $0 } }

    public static func configure(debug: Bool, sinks: [any LogSink]) {
        storage.withLock { $0 = State(debug: debug, sinks: sinks) }
    }

    public static let hotkey = LogCategory(name: "hotkey")
    public static let audio = LogCategory(name: "audio")
    public static let pipeline = LogCategory(name: "pipeline")
    public static let paste = LogCategory(name: "paste")
    public static let ui = LogCategory(name: "ui")
    public static let config = LogCategory(name: "config")

    public static func stream(_ engine: String) -> LogCategory {
        LogCategory(name: "stream.\(engine)")
    }
}
