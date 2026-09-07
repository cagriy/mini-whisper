import Foundation
import Testing

import MWOverlaySim

/// A one-for-one port of
/// `features/feature-v1-Native-Swift-macOS-rewrite/mockups/animation-studies.test.cjs`
/// onto the five new styles (design §5.3, §5.12). The constellation samples nothing —
/// it keeps its own simulation — so the response and animation assertions cover the
/// five ported styles only.
private let newStyles: [OverlayStyle] = [
    .silkRibbon, .resonantHalo, .softMeter, .liquidPearl, .petalIris,
]

@Suite struct StyleSamplerTests {
    private func sampled(
        _ style: OverlayStyle,
        t: Double,
        level: Double = 0,
        phase: StylePhase
    ) -> StyleGeometry {
        var geometry = StyleGeometry()
        StyleSampler.sample(style, time: t, level: level, phase: phase, into: &geometry)
        return geometry
    }

    private func points(_ geometry: StyleGeometry) -> [StylePoint] {
        Array(geometry.points.prefix(geometry.count))
    }

    /// The cjs `extent` helper: how far the marks spread from the centre of the card.
    private func extent(_ geometry: StyleGeometry) -> Double {
        let marks = points(geometry)
        let total = marks.reduce(0.0) { sum, point in
            sum + pow(point.x - 150, 2) + pow(point.y - 140, 2) + pow(point.height, 2)
        }
        return total / Double(marks.count)
    }

    @Test func pointCountsPerStyle() {
        #expect(
            newStyles.map(StyleSampler.pointCount) == [360, 360, 15, 180, 480]
        )
        for style in OverlayStyle.allCases {
            #expect(StyleSampler.pointCount(style) <= Constants.stylePointCapacity)
            #expect(sampled(style, t: 1.3, level: 1, phase: .speaking).count
                == StyleSampler.pointCount(style))
        }
    }

    @Test(arguments: newStyles) func everyStyleRespondsToSpeechIntensity(_ style: OverlayStyle) {
        let loud = extent(sampled(style, t: 1.3, level: 1, phase: .speaking))
        let quiet = extent(sampled(style, t: 1.3, level: 0, phase: .speaking))

        #expect(loud > quiet * 1.08)
    }

    @Test(arguments: newStyles) func processingIgnoresLevelAndStaysAnimated(_ style: OverlayStyle) {
        #expect(
            points(sampled(style, t: 2, level: 0, phase: .processing))
                == points(sampled(style, t: 2, level: 1, phase: .processing))
        )
        #expect(
            points(sampled(style, t: 2, level: 0, phase: .processing))
                != points(sampled(style, t: 3, level: 0, phase: .processing))
        )
    }

    @Test(arguments: newStyles) func quietIgnoresLevel(_ style: OverlayStyle) {
        #expect(
            points(sampled(style, t: 1, level: 0, phase: .quiet))
                == points(sampled(style, t: 1, level: 1, phase: .quiet))
        )
    }

    /// The design's deliberate departure from the mockup's single placeholder point:
    /// the layer draws the check, so the sampler emits nothing.
    @Test(arguments: OverlayStyle.allCases) func doneEmitsNoPoints(_ style: OverlayStyle) {
        #expect(sampled(style, t: 1, level: 1, phase: .done).count == 0)
        #expect(sampled(style, t: 20, level: 0, phase: .done).count == 0)
    }

    @Test(arguments: OverlayStyle.allCases)
    func everyPointFiniteAndInsideTheCard(_ style: OverlayStyle) {
        for phase in [StylePhase.quiet, .speaking, .processing, .done] {
            for t in [0.0, 1.3, 20, 500] {
                for level in [0.0, 0.5, 1] {
                    for point in points(sampled(style, t: t, level: level, phase: phase)) {
                        #expect(point.x.isFinite && point.y.isFinite)
                        #expect(point.alpha.isFinite && point.height.isFinite)
                        #expect(point.x >= 5 && point.x <= 295)
                        #expect(point.y >= 5 && point.y <= 275)
                    }
                }
            }
        }
    }

    @Test func pearlGlowFollowsTheMockup() {
        for t in [0.0, 1.3, 2.7, 20] {
            let geometry = sampled(.liquidPearl, t: t, level: 1, phase: .speaking)
            #expect(abs(geometry.glowX - (139 + 7 * sin(0.8 * t))) < 1e-12)
        }
    }

    @Test func phaseFromMode() {
        #expect(StylePhase(.starting) == .quiet)
        #expect(StylePhase(.recording) == .speaking)
        #expect(StylePhase(.processing) == .processing)
        #expect(StylePhase(.result) == .done)
        #expect(StylePhase(.error("boom")) == .quiet)
    }
}
