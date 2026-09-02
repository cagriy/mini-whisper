/// The three sounds of F34 behind a seam, so the pipeline never touches `NSSound`.
public protocol SoundPlaying: Sendable {
    func playOn()
    func playOff()
    func playTick()
}
