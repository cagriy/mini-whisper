import Foundation

public struct StreamUsage: Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var seconds: TimeInterval

    public init(inputTokens: Int = 0, outputTokens: Int = 0, seconds: TimeInterval = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.seconds = seconds
    }
}

/// `ok == false` means the caller must fall back to batch transcription (F12, F21).
public struct StreamResult: Sendable, Equatable {
    public var text: String
    public var ok: Bool
    public var usage: StreamUsage

    public init(text: String = "", ok: Bool = false, usage: StreamUsage = StreamUsage()) {
        self.text = text
        self.ok = ok
        self.usage = usage
    }
}
