import Foundation
import Testing

import MWMeetings

@Suite struct TitleSanitizerTests {
    private let date = Date(timeIntervalSince1970: 1_794_232_800)  // 2026-11-09T14:00:00Z

    @Test func slashAndColonBecomeHyphens() {
        #expect(TitleSanitizer.fileStem("Q3/Q4 review: 14:00") == "Q3-Q4 review- 14-00")
    }

    @Test func trimsAndCollapsesSpaces() {
        #expect(TitleSanitizer.fileStem("  Weekly \t sync\n  notes  ") == "Weekly sync notes")
    }

    @Test func capsAt120Characters() {
        let stem = TitleSanitizer.fileStem(String(repeating: "a", count: 119) + " bcd")
        #expect(stem == String(repeating: "a", count: 119))
        #expect(TitleSanitizer.fileStem(String(repeating: "é", count: 130)).count == 120)
    }

    @Test func fileNamesAppendTheKind() {
        #expect(TitleSanitizer.transcriptFileName("Northwind rollout sync") == "Northwind rollout sync - transcript.md")
        #expect(TitleSanitizer.summaryFileName("a/b") == "a-b - summary.md")
    }

    @Test func defaultTitleUsesTheFrontApp() {
        #expect(MeetingTitle.default(app: "Zoom", date: date, timeZone: TimeZone(identifier: "UTC")!)
            == "Zoom · 9 Nov 2026 14:00")
        #expect(MeetingTitle.default(app: "Zoom", date: date, timeZone: TimeZone(identifier: "America/New_York")!)
            == "Zoom · 9 Nov 2026 09:00")
    }

    @Test func defaultTitleWithoutAnAppIsMeeting() {
        let utc = TimeZone(identifier: "UTC")!
        #expect(MeetingTitle.default(app: nil, date: date, timeZone: utc) == "Meeting · 9 Nov 2026 14:00")
        #expect(MeetingTitle.default(app: " ", date: date, timeZone: utc) == "Meeting · 9 Nov 2026 14:00")
    }

    @Test func isDefaultMatchesTheAppAndADate() {
        #expect(MeetingTitle.isDefault("Zoom · 9 Nov 2026 14:00", app: "Zoom"))
        #expect(MeetingTitle.isDefault("Meeting · 19 Nov 2026 10:01", app: nil))
        #expect(MeetingTitle.isDefault("Meeting · 19 Nov 2026 10:01", app: " "))
        #expect(!MeetingTitle.isDefault("Teams · 9 Nov 2026 14:00", app: "Zoom"))
        #expect(!MeetingTitle.isDefault("Zoom · next week", app: "Zoom"))
        #expect(!MeetingTitle.isDefault("Northwind sync", app: "Zoom"))
        #expect(!MeetingTitle.isDefault("API Platform Options · 19 Nov 2026 10:01", app: nil))
    }

    @Test func namedReplacesTheNameAndKeepsTheDate() {
        #expect(MeetingTitle.named("API Platform Options", from: "Meeting · 19 Nov 2026 10:01")
            == "API Platform Options · 19 Nov 2026 10:01")
        #expect(MeetingTitle.named("Pricing", from: "API Platform Options · 19 Nov 2026 10:01")
            == "Pricing · 19 Nov 2026 10:01")
        #expect(MeetingTitle.named("Pricing", from: "Q3 · Q4 plans · 19 Nov 2026 10:01")
            == "Pricing · 19 Nov 2026 10:01")
    }

    @Test func namedWithoutADateIsTheSubject() {
        #expect(MeetingTitle.named("Pricing", from: "Northwind sync") == "Pricing")
    }
}
