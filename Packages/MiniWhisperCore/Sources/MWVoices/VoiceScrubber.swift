import Foundation
import MWMeetings
import MWSupport

/// Removes people's voice data from stored meetings (R21, R24): links, matches, rejections and
/// the sidecar entries of the keys their linked speakers own. Speaker names and transcripts stay.
public struct VoiceScrubber: Sendable {
    private let store: MeetingStore

    public init(store: MeetingStore) {
        self.store = store
    }

    /// Every stored meeting except `skipping` (those a session holds scrub themselves); `nil`
    /// people means everyone. A meeting that fails is logged and the walk goes on.
    public func scrub(people: Set<UUID>?, skipping: Set<UUID>) async {
        let entries: [IndexEntry]
        do {
            entries = try store.index()
        } catch {
            return Log.voice.warning("scrub: meetings unreadable: \(AnyError(error).description)")
        }
        var changed = 0
        for entry in entries where !skipping.contains(entry.id) {
            do {
                if try await scrubStored(entry.id, people: people) { changed += 1 }
            } catch {
                Log.voice.warning("scrub skipped a meeting: \(AnyError(error).description)")
            }
        }
        Log.voice.info("scrubbed \(changed) of \(entries.count) meetings")
    }

    /// Clears the links, matches and rejections naming `people` and returns the sidecar without
    /// the keys of the speakers linked to them: nil once that empties it, or for everyone.
    public static func scrub(_ meeting: inout Meeting, voices: MeetingVoices?, people: Set<UUID>?) -> MeetingVoices? {
        guard let people else {
            for index in meeting.speakers.indices {
                meeting.speakers[index].person = nil
                meeting.speakers[index].matches = []
                meeting.speakers[index].rejected = []
            }
            return nil
        }
        var removed = Set<String>()
        for index in meeting.speakers.indices {
            let speaker = meeting.speakers[index]
            if let person = speaker.person, people.contains(person) {
                removed.formUnion(ownedKeys(of: speaker))
                meeting.speakers[index].person = nil
            }
            meeting.speakers[index].matches.removeAll { $0.person.map(people.contains) ?? false }
            meeting.speakers[index].rejected.removeAll(where: people.contains)
        }
        guard var voices, voices.keys.keys.contains(where: removed.contains) else { return voices }
        voices.keys = voices.keys.filter { !removed.contains($0.key) }
        return voices.keys.isEmpty ? nil : voices
    }

    /// The sidecar keys holding a speaker's voice; the user's microphone key is the user's.
    private static func ownedKeys(of speaker: SpeakerLabel) -> Set<String> {
        Set(speaker.providerKeys + (speaker.isUser ? [MeetingVoices.userKey] : []))
    }

    /// Whether anything was written.
    private func scrubStored(_ id: UUID, people: Set<UUID>?) async throws -> Bool {
        var meeting = try store.load(id).meeting
        let original = meeting
        var voices: MeetingVoices?
        var unreadable = false
        do {
            voices = try store.readVoices(id)
        } catch {
            unreadable = true
        }
        // An unreadable sidecar is of no use to the app and may hold the voices being removed.
        let couldHoldTheirs = unreadable
            && (people.map { ids in original.speakers.contains { $0.person.map(ids.contains) ?? false } } ?? true)
        let scrubbed = Self.scrub(&meeting, voices: voices, people: people)
        var wrote = false
        // The sidecar first: should the meeting's write fail, its links still name the keys next time.
        if scrubbed != voices || couldHoldTheirs {
            if let scrubbed { try await store.writeVoices(scrubbed, of: id) } else { try await store.deleteVoices(id) }
            if couldHoldTheirs { Log.voice.warning("scrub deleted an unreadable sidecar") }
            wrote = true
        }
        if meeting != original {
            try await store.update(meeting)
            wrote = true
        }
        return wrote
    }
}
