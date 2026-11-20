import Foundation
import Testing
@testable import MiniWhisper

/// R26: what the Credits window credits, and the licence text the app ships for it.
@Suite struct CreditsTests {
    @Test func entriesAreTheModelThenSparkle() throws {
        let entries = Credits.entries
        try #require(entries.count == 2)
        let model = entries[0]
        let sparkle = entries[1]

        #expect(model.name == "WeSpeaker voice model")
        #expect(model.purpose == "Recognises voices on this Mac")
        #expect(
            model.attribution == "WeSpeaker ResNet34-LM by the WeSpeaker authors, as published by pyannote and"
                + " converted to Core ML by Fluid Inference. Bundled as a modified Core ML conversion."
        )
        #expect(model.licence == "CC BY 4.0")
        #expect(model.licenceURL == URL(string: "https://creativecommons.org/licenses/by/4.0"))
        #expect(model.licenceAddress == "creativecommons.org/licenses/by/4.0")
        #expect(model.licenceText == nil)

        #expect(sparkle.name == "Sparkle")
        #expect(sparkle.purpose == "Checks for and installs updates")
        #expect(
            sparkle.attribution == "Copyright © 2006–2017 Andy Matuschak and the Sparkle contributors. Includes"
                + " bsdiff, sais-lite and an Ed25519 implementation under their own notices."
        )
        #expect(sparkle.licence == "MIT-style licence")
        #expect(sparkle.licenceURL == nil)
        #expect(sparkle.licenceAddress == nil)
    }

    @Test func sparkleLicenceIsBundledVerbatim() throws {
        let url = try #require(Bundle.main.url(forResource: "Sparkle-LICENSE", withExtension: "txt"))
        let bundled = try String(contentsOf: url, encoding: .utf8)

        #expect(bundled.hasPrefix("Copyright (c) 2006-2013 Andy Matuschak.\n"))
        #expect(bundled.contains("EXTERNAL LICENSES"))
        #expect(Credits.entries.last?.licenceText == bundled)
    }
}
