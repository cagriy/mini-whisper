/// Word-level Levenshtein alignment with unit costs (design R15).
public struct WordAligner: Sendable {
    public struct Alignment: Sendable, Equatable {
        /// Indices into the reference and hypothesis arrays.
        public enum Op: Sendable, Equatable {
            case match(reference: Int, hypothesis: Int)
            case substitute(reference: Int, hypothesis: Int)
            case delete(reference: Int)
            case insert(hypothesis: Int)
        }

        /// In reference and hypothesis order.
        public var ops: [Op]

        public var substitutions: Int {
            ops.count { if case .substitute = $0 { true } else { false } }
        }

        public var deletions: Int {
            ops.count { if case .delete = $0 { true } else { false } }
        }

        public var insertions: Int {
            ops.count { if case .insert = $0 { true } else { false } }
        }
    }

    public init() {}

    public func align(reference: [String], hypothesis: [String]) -> Alignment {
        let (n, m) = (reference.count, hypothesis.count)
        // remaining[i][j]: the edit distance of reference[i...] against hypothesis[j...]. Walking it
        // from the start and taking the first optimal step in the order match or substitute, insert,
        // delete resolves ties the same way on every run: "webhook" / "web hook" gives
        // substitute(webhook→web), insert(hook).
        var remaining = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n, through: 0, by: -1) {
            for j in stride(from: m, through: 0, by: -1) {
                if i == n {
                    remaining[i][j] = m - j
                } else if j == m {
                    remaining[i][j] = n - i
                } else {
                    let diagonal = remaining[i + 1][j + 1] + (reference[i] == hypothesis[j] ? 0 : 1)
                    remaining[i][j] = min(diagonal, remaining[i][j + 1] + 1, remaining[i + 1][j] + 1)
                }
            }
        }

        var ops: [Alignment.Op] = []
        var (i, j) = (0, 0)
        while i < n || j < m {
            if i < n, j < m {
                let same = reference[i] == hypothesis[j]
                if remaining[i][j] == remaining[i + 1][j + 1] + (same ? 0 : 1) {
                    ops.append(same ? .match(reference: i, hypothesis: j) : .substitute(reference: i, hypothesis: j))
                    (i, j) = (i + 1, j + 1)
                    continue
                }
            }
            if j < m, remaining[i][j] == remaining[i][j + 1] + 1 {
                ops.append(.insert(hypothesis: j))
                j += 1
            } else {
                ops.append(.delete(reference: i))
                i += 1
            }
        }
        return Alignment(ops: ops)
    }
}
