import Foundation
import MWCorrections
import MWTestSupport
import Testing

/// The host-testable half of R37's harness: the manifest, the counting and the report.
/// The suite that drives real engines against real audio is `HintMeasurementTests`.
@Suite struct HintMeasurementReportTests {
    private static let manifestJSON = """
        {
          "rules": [{"heard": "eefa", "write": "Aoife", "sounds_like": ["eefa", "eva"]}],
          "vocabulary": ["xcodegen"],
          "clips": [
            {"file": "aoife-1.wav", "targets": ["Aoife"]},
            {"file": "plain-1.wav", "targets": [], "control": true}
          ]
        }
        """

    private static func manifest() throws -> HintMeasurementManifest {
        try HintMeasurementManifest.decode(Data(manifestJSON.utf8))
    }

    private static let report = HintMeasurementReport(
        engine: "SpeechAnalyzer",
        date: Date(timeIntervalSince1970: 1_757_088_420),
        decidesHintSupport: true,
        rows: [
            HintMeasurementReport.Row(
                file: "aoife-1.wav", control: false, targets: 1, hintsOff: 0, hintsOn: 1, firings: 1
            ),
            HintMeasurementReport.Row(
                file: "plain-1.wav", control: true, targets: 0, hintsOff: 0, hintsOn: 0, firings: 0
            ),
        ]
    )

    // MARK: - Manifest

    @Test func manifestDecodesWithControlDefaultingToFalse() throws {
        let manifest = try Self.manifest()

        #expect(manifest.rules.map(\.heard) == ["eefa"])
        #expect(manifest.rules.map(\.write) == ["Aoife"])
        #expect(manifest.rules.map(\.soundsLike) == [["eefa", "eva"]])
        #expect(manifest.vocabulary == ["xcodegen"])
        #expect(manifest.clips.map(\.file) == ["aoife-1.wav", "plain-1.wav"])
        #expect(manifest.clips.map(\.targets) == [["Aoife"], []])
        #expect(manifest.clips.map(\.control) == [false, true])
    }

    @Test func manifestDefaultsVocabularyAndSoundsLikeToEmpty() throws {
        let manifest = try HintMeasurementManifest.decode(
            Data(#"{"rules": [{"heard": "get hub", "write": "GitHub"}], "clips": []}"#.utf8)
        )

        #expect(manifest.rules.map(\.soundsLike) == [[]])
        #expect(manifest.vocabulary.isEmpty)
        #expect(manifest.clips.isEmpty)
    }

    @Test func manifestBuildsTheSnapshotTheResolverTakes() throws {
        let snapshot = try Self.manifest().snapshot

        #expect(snapshot.vocabulary == ["xcodegen"])
        #expect(snapshot.rules.map(\.write) == ["Aoife"])
        #expect(snapshot.rules.first?.bundleID == nil)
        #expect(snapshot.rules.first?.enabled == true)
        #expect(HintResolver.resolve(snapshot, bundleID: nil).terms
            == ["Aoife", "eefa", "eva", "xcodegen"])
    }

    // MARK: - Counting

    @Test func hitsAreCountedPerOccurrenceCaseInsensitively() {
        #expect(HintMeasurement.hits(in: "Aoife met aoife and AOIFE", targets: ["Aoife"]) == 3)
        #expect(HintMeasurement.hits(in: "Aoife ran xcodegen", targets: ["Aoife", "xcodegen"]) == 2)
        // Whole phrases only, so a longer word containing the term is not a hit.
        #expect(HintMeasurement.hits(in: "Aoifes notes", targets: ["Aoife"]) == 0)
        #expect(HintMeasurement.hits(in: "nothing here", targets: []) == 0)
    }

    @Test func aRowCountsHitsBothWaysAndTheApplierFirings() throws {
        let manifest = try Self.manifest()
        let rules = CorrectionResolver(rules: manifest.snapshot.rules).rules(for: nil)

        let row = HintMeasurement.row(
            clip: try #require(manifest.clips.first),
            hintsOff: "eefa reviewed the notes",
            hintsOn: "Aoife reviewed the notes with eva",
            rules: rules
        )

        #expect(row.file == "aoife-1.wav")
        #expect(row.control == false)
        #expect(row.targets == 1)
        #expect(row.hintsOff == 0)
        #expect(row.hintsOn == 1)
        // The rule still fires on the variant the recognizer left behind.
        #expect(row.firings == 1)
    }

    // MARK: - Report

    @Test func reportRendersOneRowPerClipWithTotals() {
        let markdown = HintMeasurement.render(Self.report)

        #expect(markdown.hasPrefix("# Hint measurement — SpeechAnalyzer\n"))
        #expect(markdown.contains("2025-09-05"))
        #expect(markdown.contains("| aoife-1.wav | 1 | 0 | 1 | 1 |"))
        #expect(markdown.contains("| plain-1.wav (control) | 0 | 0 | 0 | 0 |"))
        #expect(markdown.contains("| **Total** | 1 | 0 | 1 | 1 |"))
        #expect(HintMeasurement.fileName(Self.report) == "speechanalyzer-2025-09-05.md")
    }

    @Test func onlyTheSpeechAnalyzerReportCarriesTheVerdict() {
        var report = Self.report
        #expect(HintMeasurement.render(report).contains("**Verdict (R38):** supported"))

        // No gain in recognised targets is R38's "unavailable" half.
        report.rows[0].hintsOn = 0
        #expect(HintMeasurement.render(report).contains("**Verdict (R38):** unavailable"))

        // A false correction on a control clip is the other half.
        report.rows[0].hintsOn = 1
        report.rows[1].firings = 1
        #expect(HintMeasurement.render(report).contains("**Verdict (R38):** unavailable"))

        report.decidesHintSupport = false
        #expect(!HintMeasurement.render(report).contains("Verdict"))
    }

    @Test func theReportCarriesOnlyClipNamesAndCounts() {
        let markdown = HintMeasurement.render(Self.report)

        // No audio, and no path — the only file names are the manifest's own clip names.
        #expect(!markdown.contains("/"))
        #expect(!markdown.contains("wav\":"))
    }

    @Test func theReportDirectorySitsAboveThePackage() throws {
        let source = "/repo/Packages/MiniWhisperCore/Tests/MWStreamingTests/HintMeasurementTests.swift"

        let derived = try #require(HintMeasurement.reportDirectory(source: source, environment: [:]))
        #expect(derived.path == "/repo/features/feature-v2-Remembered-corrections/measurements")

        let overridden = try #require(HintMeasurement.reportDirectory(
            source: source, environment: ["MW_HINT_REPORT_DIR": "/tmp/mw-hint-reports"]
        ))
        #expect(overridden.path == "/tmp/mw-hint-reports")

        // Without the package in the path there is no repository root to derive.
        #expect(HintMeasurement.reportDirectory(source: "/elsewhere/file.swift", environment: [:])
            == nil)
    }
}
