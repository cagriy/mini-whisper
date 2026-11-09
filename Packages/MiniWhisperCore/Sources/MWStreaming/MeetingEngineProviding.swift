import MWConfig
import MWCorrections

/// The meeting pipeline's seam over session construction: one diarized provider
/// session per call. Separate from `EngineProvider`, so dictation fakes stay unchanged.
public protocol MeetingEngineProviding: Sendable {
    func makeMeeting(_ engine: MeetingEngine, key: String, hints: RecognitionHints) -> any StreamingEngine
}
