import MWMeetings

public enum SuggestionPolicy {
    /// A conversation match leaves the speaker open, so a later reply can replace it; a voice
    /// match outranks the conversation (R13, R17).
    public static func isOpen(_ label: SpeakerLabel) -> Bool {
        !label.isUser && label.person == nil && label.name == SpeakerLabel.defaultName(label.id)
            && !label.matches.contains { $0.source == "voice" }
    }
}
