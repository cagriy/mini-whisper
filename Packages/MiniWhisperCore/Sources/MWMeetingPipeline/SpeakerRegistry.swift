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
        let id = (labels.last?.id ?? Self.userID) + 1
        labels.append(SpeakerLabel(id: id, name: "Speaker \(id)", providerKeys: [key]))
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
    /// speaker, or into the user when either is the user.
    @discardableResult
    public mutating func rename(_ id: Int, to name: String) -> Merge? {
        guard let renamed = index(of: id) else { return nil }
        guard let existing = labels.firstIndex(where: { $0.id != id && $0.name == name }) else {
            labels[renamed].name = name
            return nil
        }
        let (from, into) = id == Self.userID ? (existing, renamed) : (renamed, existing)
        let merge = Merge(from: labels[from].id, into: labels[into].id)
        let keys = labels[from].providerKeys
        labels[into].name = name
        labels[into].providerKeys += keys
        for key in keys { owners[key] = merge.into }
        labels.remove(at: from)
        return merge
    }

    private func index(of id: Int) -> Int? {
        labels.firstIndex { $0.id == id }
    }
}
