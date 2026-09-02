/// Everything the pipeline tells the UI, on the main actor (design §5.4).
public enum UIEvent: Sendable, Equatable {
    case starting
    case recording
    /// Raw per-buffer RMS; the overlay simulation applies the floor, ceiling and envelope.
    case level(rms: Float)
    case caption(text: String, partial: Bool, dimmed: Bool)
    case captionUnavailable
    case captionNotice(String)
    case processing
    case result(String)
    case error(String)
    case idle
    case usage(today: String, month: String)
}
