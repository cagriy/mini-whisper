import Foundation
import MWMeetings

/// Past runs of a scenario, read from the meetings index (design R2, R19).
public enum TestRunHistory {
    /// One row of the Earlier runs sheet.
    public struct Run: Sendable, Equatable, Identifiable {
        /// The meeting's id.
        public var id: UUID
        public var startedAt: Date
        public var record: TestCallRecord

        public init(id: UUID, startedAt: Date, record: TestCallRecord) {
            self.id = id
            self.startedAt = startedAt
            self.record = record
        }
    }

    private static let runLimit = 50

    /// Scenario id → WER of its newest scored run at the revision `revisions` gives for it.
    /// Scenarios missing from `revisions` are left out.
    public static func latestWER(in index: [IndexEntry], revisions: [String: Int]) -> [String: Double] {
        var latest: [String: Double] = [:]
        for entry in newestFirst(index) {
            guard let tag = entry.test, let wer = tag.wer, revisions[tag.scenarioID] == tag.revision,
                  latest[tag.scenarioID] == nil else { continue }
            latest[tag.scenarioID] = wer
        }
        return latest
    }

    /// The newest 50 runs with `tag`'s scenario id and revision, newest first. A run whose record
    /// `load` cannot return is left out.
    public static func runs(
        of tag: TestCallTag,
        in index: [IndexEntry],
        load: (UUID) throws -> TestCallRecord?
    ) -> [Run] {
        let matching = index.filter { $0.test?.scenarioID == tag.scenarioID && $0.test?.revision == tag.revision }
        return newestFirst(matching).prefix(runLimit).compactMap { entry in
            guard let record = try? load(entry.id) else { return nil }
            return Run(id: entry.id, startedAt: entry.startedAt, record: record)
        }
    }

    private static func newestFirst(_ index: [IndexEntry]) -> [IndexEntry] {
        index.sorted { $0.startedAt > $1.startedAt }
    }
}
