import MWCorrections

extension HintSerializer.Capped {
    /// R26: what an engine may say about its hints — counts, never the terms
    /// themselves, which are the user's own words. Nil when there was nothing to send.
    var logLine: String? {
        guard !sent.isEmpty || !skipped.isEmpty else { return nil }
        return "hints: \(sent.count) sent, \(skipped.count) skipped"
    }
}
