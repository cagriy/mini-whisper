import Foundation

/// The Settings preview's timeline: one 13 s dictation, replayed forever, with a simulated
/// voice instead of the microphone (design §5.4). Pure, so the preview's host owns no
/// timing of its own beyond the clock.
public enum PreviewScript {
    public static let loopSeconds = Constants.previewLoopSeconds

    private static let recordingStart = Constants.previewStartingSeconds
    private static let processingStart = recordingStart + Constants.previewRecordingSeconds
    private static let resultStart = processingStart + Constants.previewProcessingSeconds

    /// `time` is seconds since the loop started; anything beyond one loop wraps.
    public static func mode(at time: Double) -> OverlayMode {
        let elapsed = time.truncatingRemainder(dividingBy: loopSeconds)
        let wrapped = elapsed < 0 ? elapsed + loopSeconds : elapsed
        return switch wrapped {
        case ..<recordingStart: .starting
        case ..<processingStart: .recording
        case ..<resultStart: .processing
        default: .result
        }
    }

    /// A raw RMS chosen so `ConstellationSimulation.normalisedLevel` returns
    /// `previewVoiceLevel · phrase(t)`, and the smoother sees what a voice would give it.
    public static func simulatedRMS(at time: Double) -> Double {
        Constants.levelFloor
            + Constants.previewVoiceLevel * phrase(at: time)
            * (Constants.levelCeil - Constants.levelFloor)
    }

    /// The mockup's "natural pauses": a slow envelope over a syllable rhythm, in (0, 1].
    public static func phrase(at time: Double) -> Double {
        let envelope = 0.18 + 0.82 * (0.5 + 0.5 * sin(time * 2.05)).squareRoot()
        let syllables = 0.55 + 0.45 * pow(sin(time * 8.2), 2)
        return envelope * syllables
    }
}
