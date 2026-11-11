import MWMeetings

/// One line of `say -v ?`.
public struct SystemVoice: Sendable, Equatable {
    public var name: String
    /// For example `en_GB`.
    public var locale: String

    public init(name: String, locale: String) {
        self.name = name
        self.locale = locale
    }
}

/// The voices installed on this Mac, in `say -v ?` listing order, and the casting of a scenario
/// onto them (design R5, §5.6 Scenario voice missing).
public struct VoiceCatalog: Sendable, Equatable {
    public let voices: [SystemVoice]

    public init(voices: [SystemVoice]) {
        self.voices = voices
    }

    /// Lines that do not read `<name>  <locale>  # <sample>` are skipped.
    public static func parse(_ listing: String) -> [SystemVoice] {
        listing.split(whereSeparator: \.isNewline).compactMap { line in
            guard let match = line.firstMatch(of: /^(.+?)\s+([a-z]{2,3}_[A-Za-z0-9]+)\s+#/) else { return nil }
            return SystemVoice(name: String(match.1), locale: String(match.2))
        }
    }

    public var english: [SystemVoice] {
        voices.filter { $0.locale.hasPrefix("en_") }
    }

    /// The names `say -v` may receive (design §5.7). A leading `-` is refused as well, so a name
    /// can never read as an option.
    public static func isAllowed(_ name: String) -> Bool {
        !name.hasPrefix("-") && name.wholeMatch(of: /[A-Za-z0-9 ()._'-]+/) != nil
    }

    /// Keeps each requested voice that is installed and allowed. A missing one becomes the first
    /// allowed English voice, in listing order, that no other role holds.
    public func cast(_ scenario: TestScenario) -> VoiceCasting {
        let candidates = english.map(\.name).filter(Self.isAllowed)
        guard Set(candidates).count >= 2 else { return .unavailable }
        let installed = Set(voices.map(\.name))
        let isUsable = { (name: String) in installed.contains(name) && Self.isAllowed(name) }
        // Kept voices are reserved first, so a role cast earlier never takes a later role's voice.
        var taken = Set(scenario.voices.map(\.requested).filter(isUsable))
        var cast: [TestCallRole: CastVoice] = [:]
        for role in scenario.voices {
            var voice = role.requested
            if !isUsable(voice) {
                guard let substitute = candidates.first(where: { !taken.contains($0) }) else { return .unavailable }
                voice = substitute
                taken.insert(substitute)
            }
            cast[role.role] = CastVoice(role: role.role, character: role.character, requested: role.requested, voice: voice)
        }
        return .ready(cast)
    }
}
