import Foundation
import MWConfig
import MWCorrections

/// R37's clip set as `$MW_HINT_AUDIO_DIR/manifest.json` declares it (design §5.3): the
/// rules and vocabulary the run resolves hints from, and the clips it transcribes.
public struct HintMeasurementManifest: Decodable, Equatable, Sendable {
    public struct Rule: Decodable, Equatable, Sendable {
        public var heard: String
        public var write: String
        public var soundsLike: [String]

        private enum CodingKeys: String, CodingKey {
            case heard, write
            case soundsLike = "sounds_like"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            heard = try container.decode(String.self, forKey: .heard)
            write = try container.decode(String.self, forKey: .write)
            soundsLike = try container.decodeIfPresent([String].self, forKey: .soundsLike) ?? []
        }
    }

    public struct Clip: Decodable, Equatable, Sendable {
        public var file: String
        public var targets: [String]
        /// A clip with no target term, which only false corrections can change.
        public var control: Bool

        private enum CodingKeys: String, CodingKey { case file, targets, control }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            file = try container.decode(String.self, forKey: .file)
            targets = try container.decodeIfPresent([String].self, forKey: .targets) ?? []
            control = try container.decodeIfPresent(Bool.self, forKey: .control) ?? false
        }
    }

    public var rules: [Rule]
    public var vocabulary: [String]
    public var clips: [Clip]

    private enum CodingKeys: String, CodingKey { case rules, vocabulary, clips }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        vocabulary = try container.decodeIfPresent([String].self, forKey: .vocabulary) ?? []
        clips = try container.decodeIfPresent([Clip].self, forKey: .clips) ?? []
    }

    public static func decode(_ data: Data) throws -> HintMeasurementManifest {
        try JSONDecoder().decode(HintMeasurementManifest.self, from: data)
    }

    /// What the run resolves hints and rules from: every manifest rule enabled and global.
    public var snapshot: CorrectionSnapshot {
        CorrectionSnapshot(
            rules: rules.map {
                CorrectionRule(heard: $0.heard, write: $0.write, soundsLike: $0.soundsLike)
            },
            vocabulary: vocabulary
        )
    }
}

/// One engine's run over the whole clip set, as the committed markdown report (R37).
public struct HintMeasurementReport: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var file: String
        public var control: Bool
        public var targets: Int
        public var hintsOff: Int
        public var hintsOn: Int
        public var firings: Int

        public init(
            file: String, control: Bool, targets: Int, hintsOff: Int, hintsOn: Int, firings: Int
        ) {
            self.file = file
            self.control = control
            self.targets = targets
            self.hintsOff = hintsOff
            self.hintsOn = hintsOn
            self.firings = firings
        }
    }

    public var engine: String
    public var date: Date
    /// R38: only SpeechAnalyzer's run decides `HintSupport.speechAnalyzer`, so only its
    /// report carries a verdict.
    public var decidesHintSupport: Bool
    public var rows: [Row]

    public init(engine: String, date: Date, decidesHintSupport: Bool, rows: [Row]) {
        self.engine = engine
        self.date = date
        self.decidesHintSupport = decidesHintSupport
        self.rows = rows
    }
}

/// The counting and rendering half of R37's harness, kept out of the shipping modules
/// and host-tested without an engine running.
public enum HintMeasurement {
    /// Occurrences of the clip's target terms in one transcript, matched the way a rule
    /// matches: whole phrases, case-insensitively.
    public static func hits(in transcript: String, targets: [String]) -> Int {
        targets.reduce(0) { total, target in
            guard let matcher = try? PhraseMatcher(variant: target) else { return total }
            return total + matcher.matches(in: transcript).count
        }
    }

    /// One clip measured both ways. Firings are counted on the hints-on transcript,
    /// which is the text the shipping pipeline would apply rules to.
    public static func row(
        clip: HintMeasurementManifest.Clip,
        hintsOff: String,
        hintsOn: String,
        rules: [ResolvedRule]
    ) -> HintMeasurementReport.Row {
        HintMeasurementReport.Row(
            file: clip.file,
            control: clip.control,
            targets: clip.targets.count,
            hintsOff: hits(in: hintsOff, targets: clip.targets),
            hintsOn: hits(in: hintsOn, targets: clip.targets),
            firings: CorrectionApplier(rules: rules).apply(to: hintsOn).replacements
        )
    }

    public static func render(_ report: HintMeasurementReport) -> String {
        var lines = [
            "# Hint measurement — \(report.engine)",
            "",
            "Date: \(day(report.date)) · clips: \(report.rows.count)",
            "",
            "| Clip | Targets | Hints off | Hints on | Rule firings |",
            "| --- | ---: | ---: | ---: | ---: |",
        ]
        for row in report.rows {
            lines.append(
                "| \(row.control ? "\(row.file) (control)" : row.file) | \(row.targets)"
                    + " | \(row.hintsOff) | \(row.hintsOn) | \(row.firings) |"
            )
        }
        let totals = self.totals(report)
        lines.append(
            "| **Total** | \(totals.targets) | \(totals.hintsOff) | \(totals.hintsOn)"
                + " | \(totals.firings) |"
        )
        if report.decidesHintSupport {
            lines.append(contentsOf: ["", verdict(report)])
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func fileName(_ report: HintMeasurementReport) -> String {
        let slug = report.engine.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(slug)-\(day(report.date)).md"
    }

    /// `features/…/measurements/` beside the package, derived from the calling test's own
    /// path so the run needs no repository root passed in. `MW_HINT_REPORT_DIR` overrides.
    public static func reportDirectory(
        source: String = #filePath,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let override = environment["MW_HINT_REPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let components = URL(fileURLWithPath: source).pathComponents
        guard let packages = components.firstIndex(of: "Packages") else { return nil }
        return components.prefix(packages)
            .reduce(URL(fileURLWithPath: "/")) { $0.appendingPathComponent($1) }
            .appendingPathComponent("features/feature-v2-Remembered-corrections/measurements")
    }

    private static func totals(
        _ report: HintMeasurementReport
    ) -> (targets: Int, hintsOff: Int, hintsOn: Int, firings: Int) {
        report.rows.reduce(into: (0, 0, 0, 0)) {
            $0.0 += $1.targets
            $0.1 += $1.hintsOff
            $0.2 += $1.hintsOn
            $0.3 += $1.firings
        }
    }

    /// R38: more target terms recognised with hints on, and no new false correction on a
    /// control clip.
    private static func verdict(_ report: HintMeasurementReport) -> String {
        let totals = self.totals(report)
        let falseCorrections = report.rows.filter(\.control).reduce(0) { $0 + $1.firings }
        let supported = totals.hintsOn > totals.hintsOff && falseCorrections == 0
        return "**Verdict (R38):** \(supported ? "supported" : "unavailable") —"
            + " \(totals.hintsOn) target terms recognised with hints on against"
            + " \(totals.hintsOff) with hints off, and \(falseCorrections) rule firings on"
            + " control clips."
    }

    private static func day(_ date: Date) -> String {
        ISO8601DateFormatter.mwMeasurementDay.string(from: date)
    }
}

extension ISO8601DateFormatter {
    /// Formatting is thread-safe; the instance is never mutated after this closure.
    nonisolated(unsafe) fileprivate static let mwMeasurementDay: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
