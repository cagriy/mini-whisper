import Foundation

/// The overlay's mode clock and everything the mode drives on the card — the fade, the
/// error shake, whether the style's marks are drawn, the label and the finish rule —
/// lifted out of `ConstellationSimulation` so every style shares one choreography
/// (design §5.6). Time only ever arrives through `advance(dt:)`.
public struct Choreography: Sendable {
    private let reduceMotion: Bool

    public private(set) var mode: OverlayMode = .starting
    public private(set) var modeTime: TimeInterval = 0
    public private(set) var showTime: TimeInterval = 0
    public private(set) var errorText = ""

    public init(reduceMotion: Bool = false) {
        self.reduceMotion = reduceMotion
    }

    public var cardAlpha: Double {
        let fadeIn = min(showTime / Constants.cardFadeSeconds, 1)
        guard case .result = mode else { return fadeIn }
        let fadeOut = (modeTime - Constants.resultHoldSeconds) / Constants.cardFadeSeconds
        return min(fadeIn, 1 - min(max(fadeOut, 0), 1))
    }

    public var shakeOffset: Double {
        guard case .error = mode, !reduceMotion else { return 0 }
        return ConstellationSimulation.shakeOffset(at: modeTime)
    }

    /// Once the shake is spent the message takes the card over (design §5.6).
    public var contentVisible: Bool {
        guard case .error = mode else { return true }
        return modeTime < Constants.shakeDuration
    }

    public var label: String {
        switch mode {
        case .starting: Constants.startingLabel
        case .processing: Constants.processingLabel
        case .recording: String(format: "%.1fs", showTime)
        case .result, .error: ""
        }
    }

    /// True once the current mode's choreography has run out and the panel should hide.
    public var isFinished: Bool {
        switch mode {
        case .result: modeTime >= Constants.resultHoldSeconds + Constants.cardFadeSeconds
        case .error: modeTime >= Constants.errorSeconds
        case .starting, .recording, .processing: false
        }
    }

    public mutating func show() {
        mode = .starting
        modeTime = 0
        showTime = 0
        errorText = ""
    }

    public mutating func set(mode: OverlayMode) {
        self.mode = mode
        modeTime = 0
        if case .error(let message) = mode {
            errorText = message
        } else {
            errorText = ""
        }
    }

    public mutating func advance(dt: TimeInterval) {
        modeTime += dt
        showTime += dt
    }
}
