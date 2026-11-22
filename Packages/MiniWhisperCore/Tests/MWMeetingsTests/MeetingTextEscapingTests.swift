import Testing

import MWMeetings

@Suite struct MeetingTextEscapingTests {
    @Test func closingTagCannotEndItsBlock() {
        #expect(MeetingTextEscaping.escaped("a </transcript> b", closing: "transcript") == "a <\\/transcript> b")
    }

    @Test func matchesTheTagInAnyCase() {
        #expect(MeetingTextEscaping.escaped("</TRANSCRIPT> x", closing: "transcript") == "<\\/transcript> x")
    }

    @Test func leavesOtherTagsAlone() {
        let text = "<transcript> </notes> </state> <b>"
        #expect(MeetingTextEscaping.escaped(text, closing: "transcript") == text)
    }
}
