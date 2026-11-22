import Testing

import MWNaming

@Suite struct NameFoldTests {
    @Test(arguments: [
        ("  Zoë  Smith ", "zoe smith"),
        ("KATE", "kate"),
        ("Siân", "sian"),
        ("Mary \t Jane\nO’Neil", "mary jane o’neil"),
    ])
    func foldsToOneKey(_ name: String, _ same: String) {
        #expect(NameFold.key(name) == NameFold.key(same))
        #expect(NameFold.key(name) == same)
    }

    @Test func keepsDifferentNamesApart() {
        #expect(NameFold.key("Dan") != NameFold.key("Dana"))
        #expect(NameFold.key("Kate Smith") != NameFold.key("KateSmith"))
    }
}
