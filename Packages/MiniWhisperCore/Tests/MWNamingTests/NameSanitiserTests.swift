import Testing

import MWNaming

@Suite struct NameSanitiserTests {
    @Test(arguments: [
        ("Kate", "Kate"),
        ("Mary-Jane O’Neil", "Mary-Jane O’Neil"),
        ("O'Neil", "O'Neil"),
        ("  Dr. Ng \n", "Dr. Ng"),
        ("Siân", "Siân"),
        (String(repeating: "a", count: 60), String(repeating: "a", count: 60)),
    ])
    func keeps(_ raw: String, _ clean: String) {
        #expect(NameSanitiser.clean(raw) == clean)
    }

    @Test(arguments: [
        "",
        "   ",
        "Speaker 4",
        "Kate2",
        "@Kate",
        "'Kate",
        "-Kate",
        String(repeating: "a", count: 61),
        "Kate <b>",
        "Kate\nSmith",
    ])
    func rejects(_ raw: String) {
        #expect(NameSanitiser.clean(raw) == nil)
    }
}
