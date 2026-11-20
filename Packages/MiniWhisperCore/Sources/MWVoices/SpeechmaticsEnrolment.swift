import Foundation

/// R10, R11: the `speakers` a Speechmatics session enrols, and the way back from a label.
public enum SpeechmaticsEnrolment {
    public static let limit = 50
    private static let prefix = "mw:"

    public struct Entry: Sendable, Equatable {
        public var person: Person
        /// `mw:<lowercase person UUID>`: Speechmatics never receives a name (R27).
        public var label: String
        public var identifier: String
    }

    /// The people holding an identifier for `tier`, most recently heard first (the identifier's
    /// date standing in for a person never heard), at most `limit`.
    public static func entries(people: [Person], tier: String) -> [Entry] {
        let held = people.compactMap { person in
            person.speechmatics[tier].map { (person: person, identifier: $0) }
        }
        return held
            .sorted { ($0.person.lastHeard ?? $0.identifier.at) > ($1.person.lastHeard ?? $1.identifier.at) }
            .prefix(limit)
            .map { Entry(person: $0.person, label: label(for: $0.person.id), identifier: $0.identifier.identifier) }
    }

    public static func label(for id: UUID) -> String {
        prefix + id.uuidString.lowercased()
    }

    /// The person whose label this is exactly, else nil: a provider label such as `S1`, a
    /// non-canonical spelling or an unknown id is an ordinary speaker.
    public static func person(forLabel label: String, among people: [Person]) -> Person? {
        guard label.hasPrefix(prefix), let id = UUID(uuidString: String(label.dropFirst(prefix.count))),
            self.label(for: id) == label
        else { return nil }
        return people.first { $0.id == id }
    }
}
