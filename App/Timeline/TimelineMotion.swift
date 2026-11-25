import SwiftUI

/// How Timeline's panels move when they play.
enum TimelineMotion {
    /// One kind of motion: how long each item takes, how far apart items start, and the curve.
    struct Track: Sendable {
        let duration: TimeInterval
        let stagger: TimeInterval
        let curve: UnitCurve

        /// How far `item` has come, 0 to 1, `time` seconds after its panel started playing.
        func progress(at time: TimeInterval, item: Int = 0) -> Double {
            let linear = (time - Double(item) * stagger) / duration
            if linear <= 0 { return 0 }
            if linear >= 1 { return 1 }
            return curve.value(at: linear)
        }

        /// Seconds from the start until the last of `items` items has finished.
        func length(items: Int) -> TimeInterval {
            items > 0 ? duration + Double(items - 1) * stagger : 0
        }

        /// The animation that moves `item` once its panel starts, `delay` seconds from now.
        func animation(item: Int = 0, after delay: TimeInterval) -> Animation {
            .timingCurve(curve, duration: duration).delay(delay + Double(item) * stagger)
        }
    }

    /// The accepted mockup's curve for bars and meters: quick to leave, slow to settle.
    private static let settle = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.2, y: 0.8), endControlPoint: UnitPoint(x: 0.2, y: 1)
    )

    /// Figures counting up.
    static let count = Track(duration: 0.9, stagger: 0, curve: .easeOut)
    /// Bars growing from the baseline.
    static let verticalBars = Track(duration: 0.6, stagger: 0.018, curve: settle)
    /// Horizontal bars and meters filling from the leading edge.
    static let horizontalBars = Track(duration: 0.7, stagger: 0.045, curve: settle)
    /// Heat cells, words and dated items fading in.
    static let fade = Track(duration: 0.45, stagger: 0.012, curve: .easeOut)
    /// Between panels that start playing together, such as those in view at opening.
    static let panelStagger: TimeInterval = 0.08
    /// The share of a panel's height that has to be inside the viewport before it plays.
    static let playThreshold: CGFloat = 0.2
}

/// Where a panel is in its play, as the charts inside it read it from the environment.
struct TimelinePlay: Equatable, Sendable {
    /// False draws the start state.
    var played: Bool
    /// Seconds from coming into view to starting.
    var delay: TimeInterval

    /// Final values at once: with Reduce Motion, and anywhere outside a playing panel.
    static let final = TimelinePlay(played: true, delay: 0)
}

extension EnvironmentValues {
    @Entry var timelinePlay = TimelinePlay.final
}

/// Which panels have played since the page last opened. A panel plays once a fifth of its height is
/// inside the viewport and stays played; panels that start together start 80 ms apart, top first.
struct PanelPlayback<Panel: Hashable> {
    /// Every panel counts as played.
    var reduceMotion: Bool

    private var playID: Int?
    private var delays: [Panel: TimeInterval] = [:]

    init(reduceMotion: Bool = false) {
        self.reduceMotion = reduceMotion
    }

    /// Whether enough of `frame` is inside `viewport`, both in the scroll view's space.
    static func shouldPlay(_ frame: CGRect, in viewport: CGRect) -> Bool {
        let inside = min(frame.maxY, viewport.maxY) - max(frame.minY, viewport.minY)
        return frame.height > 0 && inside / frame.height >= TimelineMotion.playThreshold
    }

    /// Starts over for a new opening, when `playID` is not the one already played.
    mutating func replay(_ playID: Int) {
        guard playID != self.playID else { return }
        self.playID = playID
        delays = [:]
    }

    /// Plays the panels that have come far enough into view. Returns whether any started, so a caller
    /// keeping this in observed state can skip writing it back on every scroll tick.
    @discardableResult
    mutating func update(_ frames: [Panel: CGRect], in viewport: CGRect) -> Bool {
        guard !reduceMotion else { return false }
        let starting = frames
            .filter { delays[$0.key] == nil && Self.shouldPlay($0.value, in: viewport) }
            .sorted { $0.value.minY < $1.value.minY }
        for (index, panel) in starting.enumerated() {
            delays[panel.key] = Double(index) * TimelineMotion.panelStagger
        }
        return !starting.isEmpty
    }

    func play(_ panel: Panel) -> TimelinePlay {
        if reduceMotion { return .final }
        guard let delay = delays[panel] else { return TimelinePlay(played: false, delay: 0) }
        return TimelinePlay(played: true, delay: delay)
    }
}
