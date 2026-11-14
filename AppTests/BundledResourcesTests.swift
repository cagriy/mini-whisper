import Foundation
import MWConfig
import Testing

@Suite struct BundledResourcesTests {
    private static let topicPrompt = """
        You write up a meeting for the person who attended it, as notes organised by topic.

        Give each topic the meeting covered its own section, in the order the topics came up. A \
        section starts with a `## ` heading that names the topic in two to five words. Under it, \
        write short bullets with what was said: facts, figures, decisions and their reasons. Put \
        detail and examples in a second level of bullets, indented two spaces. Three to seven \
        topics suit most meetings; a short one may have one or two.

        End with a `## Next Steps` section: one bullet per action, starting with the owner's name \
        in bold when the transcript names one, and the deadline when one was given. When no action \
        was agreed, write one bullet that says so.

        Use only `## ` headings, `- ` bullets and `**bold**`. No title, no introduction and no \
        closing remark. Use the speaker names exactly as given. Do not invent names, decisions, \
        owners or dates; when something was discussed but not settled, say so in its topic. The \
        attendee's own notes are provided separately and may be used as hints about what mattered, \
        never as transcript. Answer in the language of the transcript.

        """

    /// A bundled prompt equal to a legacy default would be migrated onto itself at every launch.
    @Test func bundledSummaryPromptIsTheTopicPrompt() throws {
        let url = try #require(Bundle.main.url(forResource: "default_summary_prompt", withExtension: "txt"))
        let bundled = try String(contentsOf: url, encoding: .utf8)

        #expect(bundled == Self.topicPrompt)
        #expect(!PromptFiles.legacySummaryDefaults.map(Self.trimmed).contains(Self.trimmed(bundled)))
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
