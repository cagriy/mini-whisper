import Foundation

/// A pure port of the animation-studies mockup's `Motion.sample` (design §5.3), expression
/// for expression, in the mockup's coordinates: origin top-left of the 300×300 card, y
/// down, motion centred on (150, 140). It writes into the caller's buffer by index and
/// never appends, so a frame costs no allocation (R17). `.quiet` is `.speaking` at zero
/// intensity, as the source has it; `.done` emits nothing and the layer draws the check.
public enum StyleSampler {
    public static func pointCount(_ style: OverlayStyle) -> Int {
        switch style {
        case .constellation: 0
        case .silkRibbon: 360
        case .resonantHalo: 360
        case .softMeter: 15
        case .liquidPearl: 180
        case .petalIris: 480
        }
    }

    public static func sample(
        _ style: OverlayStyle,
        time: Double,
        level: Double,
        phase: StylePhase,
        into geometry: inout StyleGeometry
    ) {
        guard phase != .done else {
            geometry.count = 0
            return
        }
        let processing = phase == .processing
        let e = phase == .speaking ? min(max(level, 0), 1) : 0

        switch style {
        case .constellation: break
        case .silkRibbon: silkRibbon(time: time, e: e, processing: processing, into: &geometry)
        case .resonantHalo: resonantHalo(time: time, e: e, processing: processing, into: &geometry)
        case .softMeter: softMeter(time: time, e: e, processing: processing, into: &geometry)
        case .liquidPearl: liquidPearl(time: time, e: e, processing: processing, into: &geometry)
        case .petalIris: petalIris(time: time, e: e, processing: processing, into: &geometry)
        }
        geometry.count = pointCount(style)
    }

    // MARK: - Styles

    private static let ribbonAlphas = [0.23, 0.95, 0.35]

    private static func silkRibbon(
        time: Double, e: Double, processing: Bool, into geometry: inout StyleGeometry
    ) {
        let amp = processing ? 12.0 : 3 + 53 * e
        let phase = processing ? time * 2.4 : time * 1.8
        for layer in 0..<3 {
            for i in 0..<120 {
                let u = Double(i) / 119
                let env = pow(sin(u * .pi), 1.3)
                geometry.points[layer * 120 + i] = StylePoint(
                    x: 40 + u * 220,
                    y: 140 + sin(u * .pi * 3 - phase + Double(layer) * 0.22) * amp * env
                        + (Double(layer) - 1) * 3 * env,
                    alpha: ribbonAlphas[layer]
                )
            }
        }
    }

    private static func resonantHalo(
        time: Double, e: Double, processing: Bool, into geometry: inout StyleGeometry
    ) {
        for layer in 0..<2 {
            for i in 0..<180 {
                let a = Double(i) / 179 * 2 * .pi
                let ripple = sin(a * 3 - time * 2.2) * e * 7 + cos(a * 5 + time) * e * 3
                let radius = processing
                    ? 54 + Double(layer) * 7
                    : 43 + e * 24 + sin(time * 1.5) * 1.7 + Double(layer) * 5 + ripple
                let alpha = processing
                    ? 0.15 + 0.8 * pow(max(0, cos(a - time * 1.7 - Double(layer) * 0.5)), 8)
                    : (layer == 0 ? 0.88 : 0.24)
                geometry.points[layer * 180 + i] = StylePoint(
                    x: 150 + cos(a) * radius,
                    y: 140 + sin(a) * radius,
                    alpha: alpha
                )
            }
        }
    }

    private static func softMeter(
        time: Double, e: Double, processing: Bool, into geometry: inout StyleGeometry
    ) {
        for i in 0..<15 {
            let centre = pow(sin(Double(i + 1) / 16 * .pi), 1.3)
            let syllable = 0.28 + 0.72 * pow(0.5 + 0.5 * sin(time * 7 - Double(i) * 0.63), 2)
            let scan = pow(0.5 + 0.5 * sin(Double(i) * 0.53 - time * 3), 5)
            geometry.points[i] = StylePoint(
                x: 73 + Double(i) * 11,
                y: 140,
                alpha: processing ? 0.3 + 0.65 * scan : 0.82,
                height: processing ? 7 + 27 * scan : 5 + e * 105 * centre * syllable
            )
        }
    }

    private static func liquidPearl(
        time: Double, e: Double, processing: Bool, into geometry: inout StyleGeometry
    ) {
        let spin = time * (processing ? 1.5 : 0.7)
        let base = processing ? 44.0 : 29 + e * 27
        let wobble = processing ? 4.0 : 2 + e * 6
        for i in 0..<180 {
            let a = Double(i) / 179 * 2 * .pi
            let radius = base + wobble * sin(a * 3 - spin) + e * 3 * cos(a * 5 + spin)
            geometry.points[i] = StylePoint(
                x: 150 + cos(a) * radius,
                y: 140 + sin(a) * radius,
                alpha: 0.85
            )
        }
        geometry.glowX = 139 + sin(time * 0.8) * 7
    }

    private static func petalIris(
        time: Double, e: Double, processing: Bool, into geometry: inout StyleGeometry
    ) {
        let open = processing ? 0.5 : e
        let twist = processing ? time * 0.65 : sin(time * 0.5) * 0.08
        for layer in 0..<6 {
            let rot = Double(layer) * 2 * .pi / 6 + twist
            let cosRot = cos(rot)
            let sinRot = sin(rot)
            for i in 0..<80 {
                let a = Double(i) / 79 * 2 * .pi
                let px = 13 + (1 - cos(a)) * (17 + open * 19)
                let py = sin(a) * (7 + open * 9)
                geometry.points[layer * 80 + i] = StylePoint(
                    x: 150 + px * cosRot - py * sinRot,
                    y: 140 + px * sinRot + py * cosRot,
                    alpha: 0.25 + 0.55 * (0.5 + 0.5 * sin(a + time + Double(layer)))
                )
            }
        }
    }
}
