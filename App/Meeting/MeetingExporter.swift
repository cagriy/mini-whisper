import Foundation
import MWMeetings

/// The two Markdown exports (design §5.4, R17): the same text `meetings transcript|summary`
/// prints, written where the user chose.
struct MeetingExporter {
    enum Kind: Equatable {
        case transcript, summary, both
    }

    enum Refusal: Error, Equatable, LocalizedError {
        case noSummary

        var errorDescription: String? {
            switch self {
            case .noSummary: "This meeting has no summary yet."
            }
        }
    }

    let generator: String
    let timeZone: TimeZone

    init(generator: String, timeZone: TimeZone = .current) {
        self.generator = generator
        self.timeZone = timeZone
    }

    static func suggestedNames(title: String) -> (transcript: String, summary: String) {
        (TitleSanitizer.transcriptFileName(title), TitleSanitizer.summaryFileName(title))
    }

    func transcript(_ meeting: LoadedMeeting) -> String {
        MeetingMarkdown.transcript(meeting, generator: generator, timeZone: timeZone)
    }

    func summary(_ meeting: LoadedMeeting) throws -> String {
        guard meeting.meeting.summary != nil else { throw Refusal.noSummary }
        return try MeetingMarkdown.summary(meeting, generator: generator, timeZone: timeZone)
    }

    func writeTranscript(_ meeting: LoadedMeeting, to url: URL) throws {
        try Self.write(transcript(meeting), to: url)
    }

    func writeSummary(_ meeting: LoadedMeeting, to url: URL) throws {
        try Self.write(summary(meeting), to: url)
    }

    /// Both files under their suggested names; nothing is written without a summary.
    @discardableResult
    func writeBoth(_ meeting: LoadedMeeting, folder: URL) throws -> [URL] {
        let summary = try summary(meeting)
        let names = Self.suggestedNames(title: meeting.meeting.title)
        let urls = [folder.appendingPathComponent(names.transcript), folder.appendingPathComponent(names.summary)]
        try Self.write(transcript(meeting), to: urls[0])
        try Self.write(summary, to: urls[1])
        return urls
    }

    private static func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
