import Testing

import MWNaming

@Suite struct NameSpotterTests {
    @Test(arguments: ["My name is Kate Morgan.", "Thanks, Priya, over to you."])
    func taggerFindsPersonalNames(_ text: String) {
        #expect(NameSpotter.containsName(text, known: []))
    }

    @Test func sentenceWithoutNameHasNone() {
        #expect(!NameSpotter.containsName("We ship on Friday.", known: []))
    }

    @Test(arguments: ["niamh can you hear me", "NIÁMH?", "so it was  Niamh"])
    func knownNameMatchesFoldInsensitively(_ text: String) {
        #expect(NameSpotter.containsName(text, known: ["Niamh"]))
    }

    @Test func knownMultiWordNameMatchesAcrossSpacing() {
        #expect(NameSpotter.containsName("ask mary  JANE about it", known: ["Mary Jane"]))
        #expect(!NameSpotter.containsName("ask mary about jane", known: ["Mary Jane"]))
    }

    @Test func knownNameMatchesOnWordBoundariesOnly() {
        #expect(!NameSpotter.containsName("Danger ahead", known: ["Dan"]))
        #expect(!NameSpotter.containsName("Danger ahead", known: ["  "]))
    }
}
