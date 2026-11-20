import Foundation
import MWMeetings
import MWSupport

public enum VoiceStoreError: Error, Equatable, Sendable {
    /// Another person already has the name.
    case nameTaken
    /// The user's own entry is never renamed or merged into another.
    case userEntry
    /// Blank, or a default `Speaker N`, which never names a person (R17).
    case invalidName
}

/// Owns `~/.config/mini-whisper/voices.json` (R23, R24). Changes are kept in memory even when
/// their write fails, so the next write carries them; an unreadable file is moved to
/// `voices.json.bak` and the store starts empty. Unknown ids are ignored.
public actor VoiceStore {
    private struct File: Codable {
        var schema: Int
        var people: [Person]
    }

    private static let schema = 1

    private let directory: URL
    private var cache: [Person]?

    /// Single consumer: the state after every write, including one whose write failed.
    public nonisolated let changes: AsyncStream<[Person]>
    private nonisolated let continuation: AsyncStream<[Person]>.Continuation

    private var fileURL: URL { directory.appendingPathComponent("voices.json") }
    private var backupURL: URL { directory.appendingPathComponent("voices.json.bak") }

    public init(directory: URL) {
        self.directory = directory
        (changes, continuation) = AsyncStream.makeStream()
    }

    deinit {
        continuation.finish()
    }

    // MARK: - Reads

    public func people() -> [Person] {
        current()
    }

    public func person(_ id: UUID) -> Person? {
        current().first { $0.id == id }
    }

    // MARK: - People

    /// The person with exactly this trimmed name, else a new one; nil for a blank or default
    /// speaker name.
    public func findOrCreate(named name: String, at date: Date) throws -> Person? {
        guard let name = Self.personName(name) else { return nil }
        var people = current()
        if let found = people.first(where: { $0.name == name }) { return found }
        let person = Person(name: name, createdAt: date)
        people.append(person)
        try commit(people)
        return person
    }

    /// The user's entry, created on first use; later calls return it unchanged.
    public func user(named name: String, at date: Date) throws -> Person {
        var people = current()
        if let user = people.first(where: \.isUser) { return user }
        let user = Person(name: name.trimmingCharacters(in: .whitespacesAndNewlines), isUser: true, createdAt: date)
        people.append(user)
        try commit(people)
        return user
    }

    public func rename(_ id: UUID, to name: String) throws {
        var people = current()
        guard let index = people.firstIndex(where: { $0.id == id }) else { return }
        guard !people[index].isUser else { throw VoiceStoreError.userEntry }
        guard let name = Self.personName(name) else { throw VoiceStoreError.invalidName }
        guard people[index].name != name else { return }
        guard !people.contains(where: { $0.name == name }) else { throw VoiceStoreError.nameTaken }
        people[index].name = name
        try commit(people)
    }

    /// `target` keeps its name and gains `source`'s voices; `source` becomes one of its aliases.
    public func merge(_ source: UUID, into target: UUID) throws {
        var people = current()
        guard source != target, let from = people.first(where: { $0.id == source }) else { return }
        guard !from.isUser else { throw VoiceStoreError.userEntry }
        guard let index = people.firstIndex(where: { $0.id == target }) else { return }
        var into = people[index]
        into.local = (from.local + into.local)
            .sorted { $0.at < $1.at }
            .reduce([]) { SampleSet.adding($1, to: $0) }
        into.speechmatics.merge(from.speechmatics) { kept, other in other.at > kept.at ? other : kept }
        into.speechmaticsTrusted = into.speechmaticsTrusted || from.speechmaticsTrusted
        into.lastHeard = [into.lastHeard, from.lastHeard].compactMap { $0 }.max()
        into.aliases += [from.id] + from.aliases
        people[index] = into
        people.removeAll { $0.id == source }
        try commit(people)
    }

    /// The ids to scrub from meetings: `id` and its aliases (`id` alone when it is unknown).
    public func forget(_ id: UUID) throws -> Set<UUID> {
        var people = current()
        guard let index = people.firstIndex(where: { $0.id == id }) else { return [id] }
        let forgotten = people.remove(at: index)
        try commit(people)
        return Set([id] + forgotten.aliases)
    }

    /// Deletes the file and any unreadable copy kept beside it.
    public func forgetEveryone() throws {
        cache = []
        defer { continuation.yield([]) }
        for url in [fileURL, backupURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Voices

    public func addLocalSample(_ sample: LocalSample, to id: UUID) throws {
        try update(id) { $0.local = SampleSet.adding(sample, to: $0.local) }
    }

    public func removeLocalSample(meeting: UUID, from id: UUID) throws {
        try update(id) { $0.local.removeAll { $0.meeting == meeting } }
    }

    /// Kept unless the tier already holds a newer identifier.
    public func setIdentifier(_ identifier: SpeechmaticsIdentifier, tier: String, for id: UUID) throws {
        try update(id) { person in
            if let stored = person.speechmatics[tier], stored.at > identifier.at { return }
            person.speechmatics[tier] = identifier
        }
    }

    /// Removes an identifier Speechmatics ignored; its person afterwards, or nil when no one held it.
    @discardableResult
    public func dropIdentifier(_ identifier: String) throws -> Person? {
        var people = current()
        guard let index = people.firstIndex(where: { $0.speechmatics.values.contains { $0.identifier == identifier } })
        else { return nil }
        people[index].speechmatics = people[index].speechmatics.filter { $0.value.identifier != identifier }
        try commit(people)
        return people[index]
    }

    public func setTrusted(_ trusted: Bool, for id: UUID) throws {
        try update(id) { $0.speechmaticsTrusted = trusted }
    }

    public func markHeard(_ ids: Set<UUID>, at date: Date) throws {
        var people = current()
        guard people.contains(where: { ids.contains($0.id) }) else { return }
        for index in people.indices where ids.contains(people[index].id) {
            people[index].lastHeard = date
        }
        try commit(people)
    }

    // MARK: - Internals

    private static func personName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.wholeMatch(of: /Speaker \d+/) == nil else { return nil }
        return trimmed
    }

    private func update(_ id: UUID, _ change: (inout Person) -> Void) throws {
        var people = current()
        guard let index = people.firstIndex(where: { $0.id == id }) else { return }
        change(&people[index])
        try commit(people)
    }

    private func commit(_ people: [Person]) throws {
        cache = people
        defer { continuation.yield(people) }
        try save(people)
    }

    private func current() -> [Person] {
        if let cache { return cache }
        let loaded = readFromDisk()
        cache = loaded
        return loaded
    }

    private func readFromDisk() -> [Person] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try MeetingCoding.decoder().decode(File.self, from: Data(contentsOf: fileURL)).people
        } catch {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            // No error text: a decoding error can quote the file, and the file holds names.
            Log.voice.warning("voices.json was unreadable; starting empty (backup: voices.json.bak)")
            return []
        }
    }

    private func save(_ people: [Person]) throws {
        let data = try MeetingCoding.encoder().encode(File(schema: Self.schema, people: people))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PrivateFile.replace(fileURL, with: data)
    }
}
