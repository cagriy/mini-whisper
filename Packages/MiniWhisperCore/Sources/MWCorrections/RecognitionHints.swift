/// What the engines are offered for one delivery app (R17). `rules` is an ordered array
/// rather than a dictionary because R21 fixes the entry order of `additional_vocab` and
/// R24 the order of the cleanup pairs.
public struct RecognitionHints: Equatable, Sendable {
    public struct HintRule: Equatable, Sendable {
        public var write: String
        public var soundsLike: [String]

        public init(write: String, soundsLike: [String]) {
            self.write = write
            self.soundsLike = soundsLike
        }
    }

    public var terms: [String]
    public var rules: [HintRule]
    public var vocabulary: [String]

    public static let none = RecognitionHints(terms: [], rules: [], vocabulary: [])

    public init(terms: [String], rules: [HintRule], vocabulary: [String]) {
        self.terms = terms
        self.rules = rules
        self.vocabulary = vocabulary
    }
}
