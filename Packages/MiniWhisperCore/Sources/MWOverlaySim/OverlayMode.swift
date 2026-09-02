/// What the overlay is showing (design §5.6 choreography).
public enum OverlayMode: Sendable, Equatable {
    case starting
    case recording
    case processing
    case result
    case error(String)
}
