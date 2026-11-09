import Foundation
import MWTestSupport
import Testing

import MWAgentAccess
import MWMeetings

@Suite struct MeetingIDTests {
    /// Counts every read, so a test can show that none happened.
    private final class CountingReader: MeetingReading, @unchecked Sendable {
        private let base: any MeetingReading
        private let lock = NSLock()
        private var count = 0

        init(_ base: any MeetingReading) { self.base = base }

        var reads: Int { lock.withLock { count } }

        func index() throws -> [IndexEntry] {
            lock.withLock { count += 1 }
            return try base.index()
        }

        func load(_ id: UUID) throws -> LoadedMeeting {
            lock.withLock { count += 1 }
            return try base.load(id)
        }
    }

    @Test func fullUUIDResolves() async throws {
        let seeded = try await SeededMeetings()
        let id = MeetingFixtures.northwindID

        #expect(MeetingID.resolve(id.uuidString, in: seeded.store) == .success(id))
        #expect(MeetingID.resolve(id.uuidString.lowercased(), in: seeded.store) == .success(id))
        let unknown = "00000000-0000-4000-8000-000000000000"
        #expect(MeetingID.resolve(unknown, in: seeded.store) == .failure(.notFound(unknown)))
    }

    @Test func eightHexPrefixResolvesWhenUnambiguous() async throws {
        let seeded = try await SeededMeetings()

        #expect(MeetingID.resolve("b52e04a1", in: seeded.store) == .success(SeededMeetings.standupID))
        #expect(MeetingID.resolve("7F3A9C2E-5B1D", in: seeded.store) == .success(MeetingFixtures.northwindID))
        #expect(MeetingID.resolve("0123abcd", in: seeded.store) == .failure(.notFound("0123abcd")))
    }

    @Test func ambiguousPrefixIsRejected() async throws {
        let seeded = try await SeededMeetings()

        #expect(MeetingID.resolve("7f3a9c2e", in: seeded.store) == .failure(.ambiguous("7f3a9c2e")))
    }

    @Test(arguments: ["../etc", "7f3a", "7f3a9c2g", "", "7f3a9c2e/../x", "--------", "7f3a9c2e-5b1d-4e0a-9c77-2d8f1a6b3c40-0"])
    func shortOrNonHexInputIsRejectedBeforeAnyLookup(_ input: String) async throws {
        let seeded = try await SeededMeetings()
        let reader = CountingReader(seeded.store)

        #expect(MeetingID.resolve(input, in: reader) == .failure(.invalid(input)))
        #expect(reader.reads == 0)
    }
}
