import Foundation
import MWMeetings
import MWTestSupport
import Testing

import MWVoices

@Suite struct PersonTests {
    /// The `people` array of `~/.config/mini-whisper/voices.json`.
    private struct People: Decodable {
        let schema: Int
        let people: [Person]
    }

    private let id = UUID(uuidString: "0B6F7C1E-2D3A-4B5C-8D9E-0F1A2B3C4D5E")!
    private let meeting = UUID(uuidString: "7F3A9C2E-5B1D-4E0A-9C77-2D8F1A6B3C40")!
    private let createdAt = Date(timeIntervalSince1970: 1_793_610_000)  // 2026-11-02T09:00:00Z
    private let heardAt = Date(timeIntervalSince1970: 1_795_102_200)  // 2026-11-19T15:30:00Z
    private let vector = VoiceVector((0..<VoiceVector.dimension).map { Float(sin(Double($0) / 5)) / 9 })

    private var base64: String {
        get throws { String(String(decoding: try MeetingCoding.encoder().encode(vector), as: UTF8.self).dropFirst().dropLast()) }
    }

    private var alice: Person {
        Person(
            id: id, name: "Alice", createdAt: createdAt, lastHeard: heardAt,
            local: [LocalSample(meeting: meeting, at: heardAt, seconds: 212.4, vector: vector)],
            speechmatics: ["standard": SpeechmaticsIdentifier(meeting: meeting, at: heardAt, identifier: "opaque-id")],
            speechmaticsTrusted: true
        )
    }

    @Test func decodesTheDesignShape() throws {
        let json = Data("""
            {"schema":1,"people":[{
              "id":"\(id.uuidString)","name":"Alice","isUser":false,"createdAt":"2026-11-02T09:00:00Z","lastHeard":"2026-11-19T15:30:00Z","aliases":[],
              "local":[{"meeting":"\(meeting.uuidString)","at":"2026-11-19T15:30:00Z","seconds":212.4,"vector":"\(try base64)"}],
              "speechmatics":{"standard":{"meeting":"\(meeting.uuidString)","at":"2026-11-19T15:30:00Z","identifier":"opaque-id"}},
              "speechmaticsTrusted":true}]}
            """.utf8)

        let file = try MeetingCoding.decoder().decode(People.self, from: json)

        #expect(file.schema == 1)
        #expect(file.people == [alice])
    }

    @Test func encodesItBackWithSortedKeys() throws {
        let merged = UUID(uuidString: "9A8B7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D")!
        var person = alice
        person.aliases = [merged]

        let json = String(decoding: try MeetingCoding.encoder().encode(person), as: UTF8.self)

        #expect(json == """
            {"aliases":["\(merged.uuidString)"],"createdAt":"2026-11-02T09:00:00Z","id":"\(id.uuidString)","isUser":false,\
            "lastHeard":"2026-11-19T15:30:00Z","local":[{"at":"2026-11-19T15:30:00Z","meeting":"\(meeting.uuidString)",\
            "seconds":212.4,"vector":"\(try base64)"}],"name":"Alice","speechmatics":{"standard":{"at":"2026-11-19T15:30:00Z",\
            "identifier":"opaque-id","meeting":"\(meeting.uuidString)"}},"speechmaticsTrusted":true}
            """)
        #expect(try MeetingCoding.decoder().decode(Person.self, from: Data(json.utf8)) == person)
    }

    @Test func aNewPersonHasNoSamplesNoIdentifiersAndIsUntrusted() throws {
        let person = Person(name: "Bob", createdAt: createdAt)

        #expect(person.name == "Bob")
        #expect(person.isUser == false)
        #expect(person.createdAt == createdAt)
        #expect(person.lastHeard == nil)
        #expect(person.aliases.isEmpty)
        #expect(person.local.isEmpty)
        #expect(person.speechmatics.isEmpty)
        #expect(person.speechmaticsTrusted == false)
        #expect(Person(name: "Bob", createdAt: createdAt).id != person.id)
        let json = try #require(
            try JSONSerialization.jsonObject(with: MeetingCoding.encoder().encode(person)) as? [String: Any]
        )
        #expect(json["lastHeard"] == nil)
    }
}
