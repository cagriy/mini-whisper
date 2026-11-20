import MWConfig
import MWCorrections

/// The meeting pipeline's seam over session construction: one diarized provider
/// session per call. Separate from `EngineProvider`, so dictation fakes stay unchanged.
public protocol MeetingEngineProviding: Sendable {
    /// `voices` is the session's Speechmatics enrolment; engines without one ignore it.
    func makeMeeting(
        _ engine: MeetingEngine, key: String, hints: RecognitionHints, voices: VoiceSessionConfig?
    ) -> any StreamingEngine
}
