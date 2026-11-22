import Foundation
import MWMeetings
import Testing

import MWNaming

@Suite struct SuggestionPolicyTests {
    private let kate = UUID(uuidString: "0B6F7C1E-2D3A-4B5C-8D9E-0F1A2B3C4D5E")!

    private func open(
        id: Int = 2, name: String = "Speaker 2", isUser: Bool = false, person: UUID? = nil, matches: [NameMatch] = []
    ) -> Bool {
        SuggestionPolicy.isOpen(SpeakerLabel(
            id: id, name: name, isUser: isUser, providerKeys: ["1:A", "1:B"], person: person, matches: matches
        ))
    }

    @Test func isOpen() {
        let heard = NameMatch(key: "1:A", name: "Kate", person: nil, source: "conversation", state: .suggested)
        let voice = NameMatch(key: "1:B", name: "Kate", person: kate, state: .suggested, score: 0.6)

        #expect(open())
        #expect(open(matches: [heard]))

        #expect(!open(id: 0, name: "Speaker 0", isUser: true))
        #expect(!open(name: "Kate"))
        #expect(!open(name: "Speaker 3"))
        #expect(!open(person: kate))
        #expect(!open(matches: [voice]))
        #expect(!open(matches: [heard, voice]))
    }
}
