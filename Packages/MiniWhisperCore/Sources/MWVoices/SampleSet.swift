import MWMeetings

/// A person's local samples (R20): at most `capacity`, one per meeting; a new sample replaces the
/// closest stored one at `replaceAt` or closer, else it is added and the oldest beyond capacity
/// dropped.
public enum SampleSet {
    public static let capacity = 8
    public static let replaceAt = 0.85

    /// The kept samples in their order, then `sample`.
    public static func adding(_ sample: LocalSample, to samples: [LocalSample]) -> [LocalSample] {
        // A meeting's sample is recomputed on every link, so its earlier version always goes.
        var kept = samples.filter { $0.meeting != sample.meeting }
        let scores = kept.map { $0.vector.cosine(sample.vector) }
        if let closest = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[closest] >= replaceAt {
            kept.remove(at: closest)
        }
        while kept.count >= capacity, let oldest = kept.indices.min(by: { kept[$0].at < kept[$1].at }) {
            kept.remove(at: oldest)
        }
        return kept + [sample]
    }
}
