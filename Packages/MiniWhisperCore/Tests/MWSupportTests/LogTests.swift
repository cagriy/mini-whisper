import Foundation
import Testing
@testable import MWSupport
import MWTestSupport

@Suite struct LogTests {
    private func makeTempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mw-log-\(UUID().uuidString).log")
    }

    @Test func debugFileSinkReceivesDebugLines() async throws {
        let url = makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        try await LogCapture.run(debug: true, sinks: [FileLogSink(url: url)]) {
            Log.hotkey.debug("tap installed")
        }

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

    @Test func infoOnlyWhenDebugOff() async {
        let sink = CapturingLogSink()

        await LogCapture.run(debug: false, sinks: [sink]) {
            Log.audio.debug("engine graph")
            Log.audio.info("engine started")
        }

        #expect(sink.lines == ["INFO audio engine started"])
    }

    @Test func categoriesAreNamespaced() async {
        let sink = CapturingLogSink()

        await LogCapture.run(debug: false, sinks: [sink]) {
            Log.stream("openai").warning("socket closed")
        }

        #expect(sink.records.map(\.category) == ["stream.openai"])
        #expect(sink.records.map(\.level) == [.warning])
        #expect(
            [Log.hotkey, Log.audio, Log.pipeline, Log.paste, Log.ui, Log.config].map(\.name)
                == ["hotkey", "audio", "pipeline", "paste", "ui", "config"]
        )
        #expect(Log.subsystem == "com.ips.mini-whisper")
    }
}
