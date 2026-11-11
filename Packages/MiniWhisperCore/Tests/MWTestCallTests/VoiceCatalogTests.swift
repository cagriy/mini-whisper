import Foundation
import MWMeetings
import Testing

import MWTestCall

@Suite struct VoiceCatalogTests {
    private func listing() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "say-voices", withExtension: "txt", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func catalog(without missing: Set<String> = [], adding extra: String = "") throws -> VoiceCatalog {
        let voices = VoiceCatalog.parse(extra + (try listing())).filter { !missing.contains($0.name) }
        return VoiceCatalog(voices: voices)
    }

    private func scenario(a: String, b: String) -> TestScenario {
        TestScenario(
            id: "sprint-planning",
            revision: 1,
            title: "Sprint planning",
            voices: [
                VoiceRole(role: .a, character: "Priya", requested: a),
                VoiceRole(role: .b, character: "Tom", requested: b),
            ],
            lines: [ScenarioLine(role: .a, text: "Morning, Tom.")]
        )
    }

    /// The voice cast for each role, or nil when unavailable.
    private func voices(_ casting: VoiceCasting) -> [TestCallRole: String]? {
        guard case .ready(let cast) = casting else { return nil }
        return cast.mapValues(\.voice)
    }

    @Test func parsesNamesWithSpacesAndParentheses() throws {
        let voices = VoiceCatalog.parse(try listing())

        #expect(voices.map(\.name) == [
            "Alice", "Alva", "Bad News", "Daniel", "Eddy (English (UK))", "Grandma (German (Germany))",
            "Karen", "Moira", "Rishi", "Samantha", "Tessa",
        ])
        #expect(voices.contains(SystemVoice(name: "Eddy (English (UK))", locale: "en_GB")))
        #expect(voices.contains(SystemVoice(name: "Bad News", locale: "en_US")))
        #expect(voices.contains(SystemVoice(name: "Grandma (German (Germany))", locale: "de_DE")))
    }

    @Test func parseSkipsLinesThatAreNotVoices() {
        let voices = VoiceCatalog.parse("\nnot a voice\nDaniel              en_GB    # Hello! My name is Daniel.\n")

        #expect(voices == [SystemVoice(name: "Daniel", locale: "en_GB")])
    }

    @Test func englishFilterKeepsOnlyEnLocales() throws {
        #expect(try catalog().english.map(\.name) == [
            "Bad News", "Daniel", "Eddy (English (UK))", "Karen", "Moira", "Rishi", "Samantha", "Tessa",
        ])
    }

    @Test func castsBothNamedVoicesWhenInstalled() throws {
        let casting = try catalog().cast(scenario(a: "Daniel", b: "Karen"))

        #expect(casting == .ready([
            .a: CastVoice(role: .a, character: "Priya", requested: "Daniel", voice: "Daniel"),
            .b: CastVoice(role: .b, character: "Tom", requested: "Karen", voice: "Karen"),
        ]))
    }

    @Test func substitutesAMissingVoiceInCatalogueOrder() throws {
        let catalog = try catalog(without: ["Karen"])

        let casting = catalog.cast(scenario(a: "Daniel", b: "Karen"))
        #expect(casting == .ready([
            .a: CastVoice(role: .a, character: "Priya", requested: "Daniel", voice: "Daniel"),
            .b: CastVoice(role: .b, character: "Tom", requested: "Karen", voice: "Bad News"),
        ]))
        // Bad News is the first English voice, but role B holds it.
        #expect(voices(catalog.cast(scenario(a: "Karen", b: "Bad News"))) == [.a: "Daniel", .b: "Bad News"])
    }

    @Test func substitutesBothWhenBothAreMissing() throws {
        let casting = try catalog(without: ["Karen"]).cast(scenario(a: "Fred", b: "Karen"))

        #expect(voices(casting) == [.a: "Bad News", .b: "Daniel"])
    }

    @Test func fewerThanTwoEnglishVoicesIsUnavailable() {
        let oneEnglish = VoiceCatalog(voices: [
            SystemVoice(name: "Alice", locale: "it_IT"),
            SystemVoice(name: "Daniel", locale: "en_GB"),
            SystemVoice(name: "Grandma (German (Germany))", locale: "de_DE"),
        ])

        #expect(oneEnglish.cast(scenario(a: "Daniel", b: "Karen")) == .unavailable)
        #expect(VoiceCatalog(voices: []).cast(scenario(a: "Daniel", b: "Karen")) == .unavailable)
    }

    @Test func rejectsNamesFailingTheAllowList() throws {
        let rogue = "Bad;Name            en_US    # Hello!\n-v                  en_US    # Hello!\n"
        let catalog = try catalog(adding: rogue)
        #expect(catalog.voices.prefix(2).map(\.name) == ["Bad;Name", "-v"])

        // Requested, and first in listing order: neither is cast.
        #expect(voices(catalog.cast(scenario(a: "Bad;Name", b: "-v"))) == [.a: "Bad News", .b: "Daniel"])
        #expect(voices(catalog.cast(scenario(a: "Fred", b: "Victoria"))) == [.a: "Bad News", .b: "Daniel"])

        // A rogue name does not count towards the two English voices.
        let oneUsable = VoiceCatalog(voices: [
            SystemVoice(name: "Bad;Name", locale: "en_US"),
            SystemVoice(name: "Daniel", locale: "en_GB"),
        ])
        #expect(oneUsable.cast(scenario(a: "Bad;Name", b: "Daniel")) == .unavailable)
    }

    @Test(arguments: ["Bad;Name", "-v", "-Rogue", "Bad$(touch x)", "Daniel\n", "Am\u{E9}lie", "Ame\u{301}lie", "Dan\u{200B}iel", ""])
    func isAllowedRejects(_ name: String) {
        #expect(!VoiceCatalog.isAllowed(name))
    }

    @Test(arguments: ["Daniel", "Bad News", "Eddy (English (UK))", "Mr. O'Neil-Smith_2"])
    func isAllowedAccepts(_ name: String) {
        #expect(VoiceCatalog.isAllowed(name))
    }
}
