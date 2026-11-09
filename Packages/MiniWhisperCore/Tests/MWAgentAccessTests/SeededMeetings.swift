import Foundation
import MWTestSupport

import MWMeetings

/// A `MeetingStore` in a temp directory holding, newest first: the export mockup's meeting
/// (with a summary), a short one without a summary, and one whose id shares the mockup's
/// first 8 hex characters.
struct SeededMeetings {
    static let standupID = UUID(uuidString: "b52e04a1-3c7d-4f21-a8e9-5d0c6b7a1f22")!
    static let twinID = UUID(uuidString: "7f3a9c2e-9999-4999-8999-999999999999")!

    let temp: TempDirectory
    let store: MeetingStore

    init() async throws {
        temp = try TempDirectory()
        store = MeetingStore(directory: temp.file("meetings"))
        let standup = MeetingFixtures.make(id: Self.standupID, segments: [
            Segment(speaker: 0, start: 5, end: 9, text: "The build is green and the migration ran.", session: 1),
        ])
        let twin = MeetingFixtures.make(
            id: Self.twinID, title: "Planning",
            startedAt: Date(timeIntervalSince1970: 1_794_128_400)  // 2026-11-08T09:00:00Z
        )
        for loaded in [MeetingFixtures.northwind(), standup, twin] {
            try await store.create(loaded.meeting)
            try await store.rewriteSegments(loaded.segments, of: loaded.meeting.id)
            for note in loaded.notes {
                try await store.append(note, to: loaded.meeting.id)
            }
        }
    }
}
