import Foundation
import MWMeetings

/// Maps `(session, provider label)` to stable speaker numbers (design §5.3, R11).
///
/// The user is id 0. Any other provider key gets the next number on first sight, named
/// "Speaker N"; keys carry the session, so a new session's labels number afresh until the user
/// merges them by renaming.
public struct SpeakerRegistry: Sendable, Equatable {
    public static let userID = 0

    /// A rename onto another speaker's name: every segment of `from` now belongs to `into`.
    public struct Merge: Sendable, Equatable {
        public var from: Int
        public var into: Int

        public init(from: Int, into: Int) {
            self.from = from
            self.into = into
        }
    }

    /// In id order, the user first.
    public private(set) var labels: [SpeakerLabel]
    /// Provider key → speaker id.
    private var owners: [String: Int] = [:]

    public init(userName: String) {
        self.init(labels: [SpeakerLabel(id: Self.userID, name: userName, isUser: true)])
    }

    /// Restores a stored meeting's `speakers`.
    public init(labels: [SpeakerLabel]) {
        self.labels = labels.sorted { $0.id < $1.id }
        for label in self.labels {
            for key in label.providerKeys { owners[key] = label.id }
        }
    }

    /// `"<session>:<label>"`; an unlabelled word's key is `"<session>:"`, its own speaker per
    /// session (*Planning decisions taken* #31).
    public static func key(session: Int, label: String?) -> String {
        "\(session):\(label ?? "")"
    }

    public func id(session: Int, label: String?) -> Int? {
        owners[Self.key(session: session, label: label)]
    }

    /// The speaker for a provider label, numbered on first sight one above the highest in use.
    public mutating func resolve(session: Int, label: String?) -> Int {
        let key = Self.key(session: session, label: label)
        if let id = owners[key] { return id }
        let id = nextID
        labels.append(SpeakerLabel(id: id, name: Self.defaultName(id), providerKeys: [key]))
        owners[key] = id
        return id
    }

    /// Hands a provider label to the user; a speaker it was numbered as keeps its earlier segments.
    public mutating func bindToUser(session: Int, label: String?) {
        let key = Self.key(session: session, label: label)
        guard owners[key] != Self.userID, let user = index(of: Self.userID) else { return }
        if let owner = owners[key], let previous = index(of: owner) {
            labels[previous].providerKeys.removeAll { $0 == key }
        }
        labels[user].providerKeys.append(key)
        owners[key] = Self.userID
    }

    /// Renames a speaker. Onto another speaker's name it merges the two instead, into that
    /// speaker, or into the user when either is the user. The survivor keeps its person, or takes
    /// the absorbed speaker's when it has none; matches and rejections are joined.
    @discardableResult
    public mutating func rename(_ id: Int, to name: String) -> Merge? {
        guard let renamed = index(of: id) else { return nil }
        guard let existing = labels.firstIndex(where: { $0.id != id && $0.name == name }) else {
            labels[renamed].name = name
            return nil
        }
        let (from, into) = id == Self.userID ? (existing, renamed) : (renamed, existing)
        let merge = Merge(from: labels[from].id, into: labels[into].id)
        let absorbed = labels[from]
        labels[into].name = name
        labels[into].providerKeys += absorbed.providerKeys
        labels[into].person = labels[into].person ?? absorbed.person
        for match in absorbed.matches { store(match, at: into) }
        for person in absorbed.rejected { reject(person, at: into) }
        for key in absorbed.providerKeys { owners[key] = merge.into }
        labels.remove(at: from)
        return merge
    }

    // MARK: Voice matches

    /// "Not <name>" moved `key` off speaker `from`, which keeps its other keys or its person;
    /// the key's segments now belong to the new speaker `to`.
    public struct Detach: Sendable, Equatable {
        public var key: String
        public var from: Int
        public var to: Int

        public init(key: String, from: Int, to: Int) {
            self.key = key
            self.from = from
            self.to = to
        }
    }

    /// Offers a person for the match's key, replacing an earlier match for that key. The
    /// speaker's name is left alone (R14).
    public mutating func suggest(_ match: NameMatch) {
        guard let speaker = index(owning: match.key) else { return }
        var suggestion = match
        suggestion.state = .suggested
        store(suggestion, at: speaker)
    }

    /// Names the key's speaker after a sure match, through `rename`, so a speaker already of
    /// that name absorbs it; the match stays on the survivor. `userName` is given when the
    /// match's person is the user and is the name applied instead. Only a default-named,
    /// unlinked speaker other than the user is touched (R16); otherwise nothing changes.
    public mutating func apply(_ match: NameMatch, userName: String?) -> Merge? {
        guard let speaker = index(owning: match.key) else { return nil }
        let label = labels[speaker]
        guard label.name == Self.defaultName(label.id), label.person == nil, !label.isUser else { return nil }
        let merge = rename(label.id, to: userName ?? match.name)
        var applied = match
        applied.state = .applied
        if let survivor = index(of: merge?.into ?? label.id) { store(applied, at: survivor) }
        return merge
    }

    /// Confirms the suggestion standing for `key`: the speaker is renamed after it through
    /// `rename`, and the survivor is linked to its person. Nil when no suggestion stands.
    public mutating func accept(key: String) -> (person: UUID?, merge: Merge?)? {
        guard let speaker = index(owning: key), let position = position(of: key, .suggested, at: speaker) else {
            return nil
        }
        let match = labels[speaker].matches[position]
        let id = labels[speaker].id
        let merge = rename(id, to: match.name)
        if let survivor = index(of: merge?.into ?? id) {
            if let person = match.person { labels[survivor].person = person }
            labels[survivor].matches.removeAll { $0.key == key }
        }
        return (match.person, merge)
    }

    /// Drops the suggestion standing for `key`; its person is not offered to that speaker again.
    @discardableResult
    public mutating func dismiss(key: String) -> NameMatch? {
        guard let speaker = index(owning: key), let position = position(of: key, .suggested, at: speaker) else {
            return nil
        }
        let match = labels[speaker].matches.remove(at: position)
        reject(match.person, at: speaker)
        return match
    }

    /// "Not <name>" on the name applied for `key`. A speaker owning only that key, unlinked and
    /// not the user, returns to `Speaker <id>`; otherwise the key moves to a new speaker, returned
    /// so its segments can follow. The user is never given a default name. Either way the person
    /// is not offered for that voice again.
    public mutating func detach(key: String) -> Detach? {
        guard let speaker = index(owning: key), let position = position(of: key, .applied, at: speaker) else {
            return nil
        }
        let match = labels[speaker].matches.remove(at: position)
        let label = labels[speaker]
        if label.providerKeys == [key], label.person == nil, !label.isUser {
            labels[speaker].name = Self.defaultName(label.id)
            reject(match.person, at: speaker)
            return nil
        }
        labels[speaker].providerKeys.removeAll { $0 == key }
        let id = nextID
        labels.append(SpeakerLabel(
            id: id, name: Self.defaultName(id), providerKeys: [key], rejected: match.person.map { [$0] } ?? []
        ))
        owners[key] = id
        return Detach(key: key, from: label.id, to: id)
    }

    /// Links a speaker to `person`, or unlinks it with nil. Its matches go, and a person they
    /// offered other than `person` is not offered to that speaker again.
    public mutating func link(_ id: Int, person: UUID?) {
        guard let speaker = index(of: id) else { return }
        let removed = labels[speaker].matches
        labels[speaker].person = person
        labels[speaker].matches = []
        for match in removed where match.person != person { reject(match.person, at: speaker) }
    }

    // MARK: Helpers

    /// One above the highest id in use.
    private var nextID: Int {
        (labels.last?.id ?? Self.userID) + 1
    }

    private static func defaultName(_ id: Int) -> String {
        "Speaker \(id)"
    }

    private func index(of id: Int) -> Int? {
        labels.firstIndex { $0.id == id }
    }

    private func index(owning key: String) -> Int? {
        owners[key].flatMap(index(of:))
    }

    private func position(of key: String, _ state: NameMatch.State, at speaker: Int) -> Int? {
        labels[speaker].matches.firstIndex { $0.key == key && $0.state == state }
    }

    /// At most one match per provider key.
    private mutating func store(_ match: NameMatch, at speaker: Int) {
        if let position = labels[speaker].matches.firstIndex(where: { $0.key == match.key }) {
            labels[speaker].matches[position] = match
        } else {
            labels[speaker].matches.append(match)
        }
    }

    private mutating func reject(_ person: UUID?, at speaker: Int) {
        guard let person, !labels[speaker].rejected.contains(person) else { return }
        labels[speaker].rejected.append(person)
    }
}
