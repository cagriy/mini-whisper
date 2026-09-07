import Foundation
import Testing

import MWOverlaySim

/// The Settings preview's 13 s timeline and its simulated voice (design §5.4, §5.12).
@Suite struct PreviewScriptTests {
    @Test func modeBoundaries() {
        #expect(PreviewScript.loopSeconds == Constants.previewLoopSeconds)

        let expected: [(Double, OverlayMode)] = [
            (0, .starting), (1.999, .starting),
            (2, .recording), (7.999, .recording),
            (8, .processing), (11.499, .processing),
            (11.5, .result), (12.999, .result),
            (13, .starting), (15, .recording), (24.5, .result),
        ]
        for (time, mode) in expected {
            #expect(PreviewScript.mode(at: time) == mode)
        }
    }

    @Test func simulatedRMSMapsThroughNormalisedLevel() {
        for step in 0...260 {
            let time = Double(step) / 20
            let normalised = ConstellationSimulation.normalisedLevel(
                rms: PreviewScript.simulatedRMS(at: time)
            )
            let expected = Constants.previewVoiceLevel * PreviewScript.phrase(at: time)
            #expect(abs(normalised - expected) < 1e-12)
        }
    }

    @Test func phraseStaysInsideZeroToOne() {
        for step in 0...2600 {
            let phrase = PreviewScript.phrase(at: Double(step) / 200)
            #expect(phrase > 0)
            #expect(phrase <= 1)
        }
    }
}
