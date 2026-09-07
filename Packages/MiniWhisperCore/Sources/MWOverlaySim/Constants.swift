import Foundation

/// Every overlay number, ported value for value from
/// `../mini-whisper-py/src/mini_whisper/overlay.py:11-60` plus the Breathing choreography of
/// design §5.6.
///
/// | Swift | overlay.py | Value |
/// |---|---|---|
/// | `dotCount` | `NUM_DOTS` | 24 |
/// | `windowSize` | `WINDOW_SIZE` | 300 |
/// | `dotAreaRadius` | `DOT_AREA_RADIUS` | 100 |
/// | `ringDotCount` | `NUM_RING_DOTS` | 10 |
/// | `ringRadialJitter` | `RING_RADIAL_JITTER` | 0.10 |
/// | `ringAngularJitter` | `RING_ANGULAR_JITTER` | 0.15 |
/// | `dotRadiusMin` / `dotRadiusMax` | `DOT_RADIUS_MIN` / `_MAX` | 2 / 5 |
/// | `connectionDistance` | `CONNECTION_DISTANCE` | 120 |
/// | `backgroundCornerRadius` | `BG_CORNER_RADIUS` | 20 |
/// | `backgroundAlpha` | `BG_ALPHA` | 0.7 |
/// | `springK` | `SPRING_K` | 30 |
/// | `damping` | `DAMPING` | 10 |
/// | `ambientAmplitude` | `AMBIENT_AMPLITUDE` | 10 |
/// | `ambientSpeed` | `AMBIENT_SPEED` | 1.2 |
/// | `audioAmplitude` | `AUDIO_AMPLITUDE` | 130 |
/// | `processingRotationSpeed` | `PROCESSING_ROTATION_SPEED` | 3 |
/// | `audioAngleDrift` | `AUDIO_ANGLE_DRIFT` | 2 |
/// | `audioAngleBoost` | `AUDIO_ANGLE_BOOST` | 40 |
/// | `levelFloor` / `levelCeil` | `LEVEL_FLOOR` / `LEVEL_CEIL` | 0.005 / 0.06 |
/// | `smoothAttack` / `smoothDecay` | `SMOOTH_ATTACK` / `SMOOTH_DECAY` | 0.6 / 0.08 |
/// | `maxTimestep` | `min(now - last, 0.05)` in `_tick` | 0.05 |
/// | `caption*` | the `CAPTION_*` block | as listed below |
///
/// `linkAlphaScale`, `dotAlpha` and everything under "Choreography" have no `overlay.py`
/// counterpart: they come from design §5.6 and the accepted Breathing mockup.
public enum Constants {
    // MARK: - Dots
    public static let dotCount = 24
    public static let windowSize = 300.0
    public static let dotAreaRadius = 100.0
    public static let ringDotCount = 10
    public static let ringRadialJitter = 0.10
    public static let ringAngularJitter = 0.15
    public static let dotRadiusMin = 2.0
    public static let dotRadiusMax = 5.0
    public static let dotAlpha = 0.9
    public static let connectionDistance = 120.0
    public static let linkAlphaScale = 0.6
    public static let backgroundCornerRadius = 20.0
    public static let backgroundAlpha = 0.7
    public static let maxLinks = dotCount * (dotCount - 1) / 2

    // MARK: - Physics
    public static let springK = 30.0
    public static let damping = 10.0
    public static let ambientAmplitude = 10.0
    public static let ambientSpeed = 1.2
    public static let audioAmplitude = 130.0
    public static let processingRotationSpeed = 3.0
    public static let audioAngleDrift = 2.0
    public static let audioAngleBoost = 40.0
    public static let maxTimestep = 0.05

    // MARK: - Audio level
    public static let levelFloor = 0.005
    public static let levelCeil = 0.06
    public static let smoothAttack = 0.6
    public static let smoothDecay = 0.08

    // MARK: - Choreography (design §5.6)
    public static let cardFadeSeconds = 0.12
    public static let breathingRingRadius = 30.0
    public static let breathingRingAmplitude = 6.0
    public static let breathingPeriod = 1.0
    public static let resultHoldSeconds = 0.26
    public static let shakeAmplitude = 6.0
    public static let shakeFrequency = 60.0
    public static let shakeDuration = 0.45
    /// F14: an error stays on screen for three seconds, shake included.
    public static let errorSeconds = 3.0
    public static let startingLabel = "starting…"
    public static let processingLabel = "processing..."

    // MARK: - Caption bar
    public static let captionWidth = 480.0
    public static let captionGap = 14.0
    public static let captionCornerRadius = 16.0
    public static let captionBackgroundAlpha = 0.7
    public static let captionFontSize = 14.0
    public static let captionLineHeight = 22.0
    public static let captionPaddingH = 16.0
    public static let captionPaddingV = 13.0
    public static let captionMaxLines = 7
    public static let captionHeight =
        Double(captionMaxLines) * captionLineHeight + 2 * captionPaddingV
    public static let captionCurrentAlpha = 0.92
    public static let captionOlderAlpha = 0.45
    public static let captionDimmedAlpha = 0.65
    public static let captionDimmedOlderAlpha = 0.40
    public static let captionCursor = "▍"
    public static let captionBlinkSeconds = 0.9
    public static let captionUnavailableText = "⚠ live transcript unavailable"
}
