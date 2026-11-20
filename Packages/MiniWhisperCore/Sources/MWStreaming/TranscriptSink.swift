public protocol TranscriptSink: AnyObject, Sendable {
    /// Full current-segment text; replaces the previous partial.
    func onPartial(_ text: String)
    /// A segment is finalised; append to the compound transcript.
    func onFinal(_ text: String)
    func onEngineError(_ error: any Error)
    /// A diarized segment, delivered beside its `onFinal`.
    func onSegment(_ segment: TranscriptSegment)
    func onSpeakerRevision(_ revisions: [SpeakerRevision])
    func onSessionLimit(_ limit: SessionLimit)
    func onSpeakers(_ speakers: [ProviderSpeaker])
    /// A remembered voice the provider refused; nils when it did not say which.
    func onIdentifierIgnored(label: String?, identifier: String?)
}

extension TranscriptSink {
    public func onSegment(_ segment: TranscriptSegment) {}
    public func onSpeakerRevision(_ revisions: [SpeakerRevision]) {}
    public func onSessionLimit(_ limit: SessionLimit) {}
    public func onSpeakers(_ speakers: [ProviderSpeaker]) {}
    public func onIdentifierIgnored(label: String?, identifier: String?) {}
}
