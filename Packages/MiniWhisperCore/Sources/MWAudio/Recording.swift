import Foundation

public struct Recording: Sendable, Equatable {
    public let wav: Data
    public let duration: TimeInterval
    public let meanRMS: Float

    public init(wav: Data, duration: TimeInterval, meanRMS: Float) {
        self.wav = wav
        self.duration = duration
        self.meanRMS = meanRMS
    }
}
