public protocol TranscriptSink: AnyObject, Sendable {
    /// Full current-segment text; replaces the previous partial.
    func onPartial(_ text: String)
    /// A segment is finalised; append to the compound transcript.
    func onFinal(_ text: String)
    func onEngineError(_ error: any Error)
}
