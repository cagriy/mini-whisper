import AVFAudio

public protocol BufferListener: AnyObject, Sendable {
    func feed(_ buffer: AVAudioPCMBuffer)
}
