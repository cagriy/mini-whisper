/// One mark in a style's geometry, in the mockup's card space. `height` is the soft
/// meter's stroke length and stays 0 for every other style.
public struct StylePoint: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var alpha: Double
    public var height: Double

    public init(x: Double = 0, y: Double = 0, alpha: Double = 0, height: Double = 0) {
        self.x = x
        self.y = y
        self.alpha = alpha
        self.height = height
    }
}

/// A style's marks for one frame. `points` is sized once to `stylePointCapacity` and
/// never grows — `count` says how many are live, so a frame costs no allocation (R17).
public struct StyleGeometry: Sendable {
    public internal(set) var points: [StylePoint]
    public internal(set) var count: Int
    public internal(set) var glowX: Double

    public init() {
        points = Array(repeating: StylePoint(), count: Constants.stylePointCapacity)
        count = 0
        glowX = 0
    }
}

/// What the sampler draws, one step coarser than `OverlayMode`: the error card shows the
/// style's quiet form until the shake is spent, and the result card its completion mark.
public enum StylePhase: Sendable, Equatable {
    case quiet
    case speaking
    case processing
    case done

    public init(_ mode: OverlayMode) {
        switch mode {
        case .starting, .error: self = .quiet
        case .recording: self = .speaking
        case .processing: self = .processing
        case .result: self = .done
        }
    }
}
