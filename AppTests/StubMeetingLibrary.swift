import Foundation
import MWMeetings
@testable import MiniWhisper

/// The store as the list sees it: index entries plus whatever loads.
final class StubMeetingLibrary: MeetingLibrary, @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [IndexEntry]
    private var _meetings: [UUID: LoadedMeeting] = [:]
    private var _indexMissing = false
    private var _refreshes = 0
    private var _loads = 0
    private var _deleted: [UUID] = []
    private var _audioDeleted: [UUID] = []
    private var _retitled: [String] = []

    init(_ entries: [IndexEntry] = [], meetings: [LoadedMeeting] = []) {
        _entries = entries
        for meeting in meetings { _meetings[meeting.meeting.id] = meeting }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    var indexMissing: Bool {
        get { locked { _indexMissing } }
        set { locked { _indexMissing = newValue } }
    }

    var refreshes: Int { locked { _refreshes } }
    var loads: Int { locked { _loads } }
    var deleted: [UUID] { locked { _deleted } }
    var audioDeleted: [UUID] { locked { _audioDeleted } }
    var retitled: [String] { locked { _retitled } }

    var isIndexMissing: Bool { indexMissing }

    func index() throws -> [IndexEntry] { locked { _entries } }

    func load(_ id: UUID) throws -> LoadedMeeting {
        try locked {
            _loads += 1
            guard let meeting = _meetings[id] else { throw CocoaError(.fileNoSuchFile) }
            return meeting
        }
    }

    func refreshIndex() async throws -> [IndexEntry] {
        locked {
            _refreshes += 1
            _indexMissing = false
            return _entries
        }
    }

    func delete(_ id: UUID) async throws {
        locked {
            _deleted.append(id)
            _entries.removeAll { $0.id == id }
        }
    }

    func deleteAudio(_ id: UUID) async throws {
        locked {
            _audioDeleted.append(id)
            if let index = _entries.firstIndex(where: { $0.id == id }) { _entries[index].audioBytes = 0 }
        }
    }

    func retitle(_ id: UUID, to title: String) async throws {
        locked {
            _retitled.append(title)
            if let index = _entries.firstIndex(where: { $0.id == id }) { _entries[index].title = title }
        }
    }
}
