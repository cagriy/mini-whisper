import CoreGraphics
import MWConfig

/// The frame the main window opens with (design §5.8): the stored one while it still lies
/// on a connected display, otherwise the default. Pure, over the screens' visible frames.
enum WindowFramePolicy {
    struct Screens {
        /// Every connected screen's visible frame.
        var visible: [CGRect]
        /// The main screen's visible frame.
        var main: CGRect?
    }

    static let defaultSize = CGSize(width: 1080, height: 720)
    static let minimumSize = CGSize(width: 900, height: 600)
    /// What a stored frame must show of itself on a screen to be kept.
    private static let minimumOverlap: CGFloat = 100

    static func frame(saved: WindowFrame?, screens: Screens) -> CGRect {
        guard let saved else { return defaultFrame(on: screens.main) }
        let stored = CGRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
        guard let screen = screen(holding: stored, in: screens.visible) else { return defaultFrame(on: screens.main) }
        let width = min(max(stored.size.width, minimumSize.width), screen.width)
        let height = min(max(stored.size.height, minimumSize.height), screen.height)
        return CGRect(
            x: min(max(stored.origin.x, screen.minX), screen.maxX - width),
            y: min(max(stored.origin.y, screen.minY), screen.maxY - height),
            width: width,
            height: height
        )
    }

    /// The screen showing most of `frame`, if any shows enough of it.
    private static func screen(holding frame: CGRect, in screens: [CGRect]) -> CGRect? {
        screens
            .map { (screen: $0, overlap: $0.intersection(frame)) }
            .filter { $0.overlap.width >= minimumOverlap && $0.overlap.height >= minimumOverlap }
            .max { $0.overlap.width * $0.overlap.height < $1.overlap.width * $1.overlap.height }?
            .screen
    }

    private static func defaultFrame(on main: CGRect?) -> CGRect {
        guard let main else { return CGRect(origin: .zero, size: defaultSize) }
        return CGRect(
            x: main.midX - defaultSize.width / 2,
            y: main.midY - defaultSize.height / 2,
            width: defaultSize.width,
            height: defaultSize.height
        )
    }
}
