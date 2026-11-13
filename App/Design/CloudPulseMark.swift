import SwiftUI

/// The cloud-and-pulse mark of the app icon, for empty states and About: an open outline, to be
/// stroked with round caps and joins. It keeps its 48 by 32 proportions, centred in the frame.
struct CloudPulseMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 13, y: 23))
        path.addClockwiseArc(to: CGPoint(x: 14, y: 9.1), radius: 7)
        path.addClockwiseArc(to: CGPoint(x: 32.4, y: 8), radius: 9.5)
        path.addClockwiseArc(to: CGPoint(x: 35, y: 23), radius: 7.5)

        path.move(to: CGPoint(x: 4, y: 27))
        for point in [(18, 27), (21, 20), (25, 31), (28, 23), (30, 27), (44, 27)] {
            path.addLine(to: CGPoint(x: point.0, y: point.1))
        }

        let scale = min(rect.width / 48, rect.height / 32)
        return path.applying(
            CGAffineTransform(translationX: rect.midX - 24 * scale, y: rect.midY - 16 * scale).scaledBy(x: scale, y: scale)
        )
    }
}

private extension Path {
    /// The SVG arc the mark is drawn with: the short way to `end` round a circle of `radius`, clockwise.
    mutating func addClockwiseArc(to end: CGPoint, radius: CGFloat) {
        guard let start = currentPoint else { return }
        let half = CGPoint(x: (start.x - end.x) / 2, y: (start.y - end.y) / 2)
        let squared = half.x * half.x + half.y * half.y
        let reach = (max(0, radius * radius - squared) / squared).squareRoot()
        let center = CGPoint(x: (start.x + end.x) / 2 + reach * half.y, y: (start.y + end.y) / 2 - reach * half.x)
        let from = atan2(start.y - center.y, start.x - center.x)
        var sweep = atan2(end.y - center.y, end.x - center.x) - from
        if sweep < 0 { sweep += 2 * .pi }
        addRelativeArc(center: center, radius: radius, startAngle: .radians(from), delta: .radians(sweep))
    }
}
