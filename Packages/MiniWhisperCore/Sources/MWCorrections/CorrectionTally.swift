import Foundation
import MWConfig

/// R2: how often each phrase has been corrected, in its first-seen spelling, bounded so
/// the config cannot grow without limit.
public enum CorrectionTally {
    public struct TallyRow: Equatable, Sendable {
        public var heard: String
        public var count: Int
        public var hasRule: Bool
    }

    static let cap = 200

    public static func incremented(
        _ tally: [CorrectionTallyEntry],
        heard: String,
        now: Date
    ) -> [CorrectionTallyEntry] {
        var tally = tally
        let key = PhraseKey.key(heard)
        if let index = tally.firstIndex(where: { PhraseKey.key($0.heard) == key }) {
            tally[index].count += 1
            tally[index].last = now
            return tally
        }
        // The phrase just corrected is the one worth keeping, so the weakest entry goes
        // before the append rather than after it.
        if tally.count >= cap, let weakest = weakestIndex(of: tally) {
            tally.remove(at: weakest)
        }
        tally.append(
            CorrectionTallyEntry(heard: PhraseKey.normalised(heard), count: 1, last: now)
        )
        return tally
    }

    public static func top(
        _ tally: [CorrectionTallyEntry],
        limit: Int = 5,
        rules: [CorrectionRule]
    ) -> [TallyRow] {
        let remembered = Set(
            rules.filter(\.enabled).flatMap { [$0.heard] + $0.soundsLike }.map(PhraseKey.key)
        )
        return
            tally
            .sorted {
                $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last
            }
            .prefix(limit)
            .map {
                TallyRow(
                    heard: $0.heard,
                    count: $0.count,
                    hasRule: remembered.contains(PhraseKey.key($0.heard))
                )
            }
    }

    private static func weakestIndex(of tally: [CorrectionTallyEntry]) -> Int? {
        tally.indices.min {
            tally[$0].count != tally[$1].count
                ? tally[$0].count < tally[$1].count
                : tally[$0].last < tally[$1].last
        }
    }
}
