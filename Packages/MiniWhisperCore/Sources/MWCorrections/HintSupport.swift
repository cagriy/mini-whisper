/// R38: whether SpeechAnalyzer's `AnalysisContext` hint path has a measured effect. The
/// measurement stage replaces this constant's value; the README mirrors it.
public enum HintSupport: Equatable, Sendable {
    case supported
    case unavailable(reason: String)

    public static let speechAnalyzer: HintSupport = .unavailable(reason: "effect not yet measured")
}
