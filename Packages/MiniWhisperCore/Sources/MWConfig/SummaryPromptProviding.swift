/// The summariser's system prompt. Lives beside `PromptFiles`, not in the meeting
/// pipeline, so fakes need no new dependency edge.
public protocol SummaryPromptProviding: Sendable {
    func summaryPrompt() throws -> String
}
