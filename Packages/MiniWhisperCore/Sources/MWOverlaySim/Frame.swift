public struct DotState: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var radius: Double

    public init(x: Double = 0, y: Double = 0, radius: Double = 0) {
        self.x = x
        self.y = y
        self.radius = radius
    }
}

/// A line between `dots[a]` and `dots[b]`.
public struct Link: Sendable, Equatable {
    public var a: Int
    public var b: Int
    public var alpha: Double

    public init(a: Int = 0, b: Int = 0, alpha: Double = 0) {
        self.a = a
        self.b = b
        self.alpha = alpha
    }
}

/// One rendered frame. `dots` and `links` are sized once and never grow — `linkCount` says
/// how many links are live, so 60 fps costs no allocation (design §5.6, N1).
public struct Frame: Sendable {
    public internal(set) var dots: [DotState]
    public internal(set) var links: [Link]
    public internal(set) var linkCount: Int
    public internal(set) var cardAlpha: Double
    /// Horizontal shake offset applied to the whole card (error mode).
    public internal(set) var offsetX: Double
    public internal(set) var label: String
    public internal(set) var errorText: String
    public internal(set) var dotsVisible: Bool

    init(dotCount: Int, linkCapacity: Int) {
        dots = Array(repeating: DotState(), count: dotCount)
        links = Array(repeating: Link(), count: linkCapacity)
        linkCount = 0
        cardAlpha = 0
        offsetX = 0
        label = ""
        errorText = ""
        dotsVisible = true
    }
}
