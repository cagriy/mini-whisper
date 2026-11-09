import AppKit
import MWMeetings
import MWSupport
import UniformTypeIdentifiers

/// Where an export goes (design §5.4, §5.7): a save panel per file, a folder for *Export both*,
/// and an alert instead of a panel when there is no summary to export.
@MainActor
enum ExportPanels {
    static func export(
        _ kind: MeetingExporter.Kind, of id: UUID, from reader: any MeetingReading, exporter: MeetingExporter
    ) {
        do {
            let meeting = try reader.load(id)
            if kind != .transcript { _ = try exporter.summary(meeting) }
            let names = MeetingExporter.suggestedNames(title: meeting.meeting.title)
            switch kind {
            case .transcript:
                guard let url = save(name: names.transcript) else { return }
                try exporter.writeTranscript(meeting, to: url)
            case .summary:
                guard let url = save(name: names.summary) else { return }
                try exporter.writeSummary(meeting, to: url)
            case .both:
                guard let folder = chooseFolder() else { return }
                let existing = [names.transcript, names.summary].filter {
                    FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
                }
                guard existing.isEmpty || confirmReplacing(existing) else { return }
                try exporter.writeBoth(meeting, folder: folder)
            }
        } catch {
            Log.meeting.warning("export failed: \(AnyError(error).description)")
            alert(AnyError(error).description)
        }
    }

    private static func save(name: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder for the transcript and the summary."
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The folder panel, unlike the save panel, does not ask before replacing.
    private static func confirmReplacing(_ names: [String]) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace the existing files?"
        alert.informativeText = names.joined(separator: "\n")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
