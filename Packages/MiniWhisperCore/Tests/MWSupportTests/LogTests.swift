import Foundation
import Testing
@testable import MWSupport
import MWTestSupport

/// Serialized: `Log.configure` installs process-wide sinks.
@Suite(.serialized) struct LogTests {
    private func makeTempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mw-log-\(UUID().uuidString).log")
    }

    @Test func debugFileSinkReceivesDebugLines() throws {
        let url = makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        Log.configure(debug: true, sinks: [FileLogSink(url: url)])
        defer { Log.configure(debug: false, sinks: []) }

        Log.hotkey.debug("tap installed")

        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 1)
        let line = try #require(lines.first).description
        #expect(line.hasSuffix(" DEBUG hotkey tap installed"))
        let timestamp = String(line.prefix(while: { $0 != " " }))
        #expect(ISO8601DateFormatter.mwLog.date(from: timestamp) != nil)

        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.int16Value == 0o600)
    }

    @Test func infoOnlyWhenDebugOff() {
        let sink = CapturingLogSink()
        Log.configure(debug: false, sinks: [sink])
        defer { Log.configure(debug: false, sinks: []) }

        Log.audio.debug("engine graph")
        Log.audio.info("engine started")

        let audio = sink.lines.filter { $0.hasSuffix(" audio engine graph") || $0.hasSuffix(" audio engine started") }
        #expect(audio == ["INFO audio engine started"])
    }

    @Test func categoriesAreNamespaced() {
        let sink = CapturingLogSink()
        Log.configure(debug: false, sinks: [sink])
        defer { Log.configure(debug: false, sinks: []) }

        Log.stream("openai").warning("socket closed")

        #expect(sink.records.contains { $0.category == "stream.openai" && $0.level == .warning })
        #expect(
            [Log.hotkey, Log.audio, Log.pipeline, Log.paste, Log.ui, Log.config].map(\.name)
                == ["hotkey", "audio", "pipeline", "paste", "ui", "config"]
        )
        #expect(Log.subsystem == "com.ips.mini-whisper")
    }
}
