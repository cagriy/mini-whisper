import MWConfig

/// The rules and vocabulary a single recording works from, taken once at press so a
/// config edit mid-recording applies from the next one (R12).
public struct CorrectionSnapshot: Equatable, Sendable {
    public var rules: [CorrectionRule]
    public var vocabulary: [String]

    public init(rules: [CorrectionRule], vocabulary: [String]) {
        self.rules = rules
        self.vocabulary = vocabulary
    }

    public init(config: Config) {
        self.init(rules: config.corrections, vocabulary: config.vocabulary)
    }
}
