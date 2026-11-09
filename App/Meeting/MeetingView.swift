import AppKit
import MWMeetingPipeline
import MWMeetings
import SwiftUI

/// The meeting window: the chooser until Start, then the live transcript with the notes pane
/// (accepted mockup `mockup-v4-meeting-window.html`, States 1–2).
struct MeetingView: View {
    let model: MeetingWindowModel
    let actions: MeetingActions

    var body: some View {
        Group {
            if model.state == .idle {
                MeetingChooserView(model: model, actions: actions)
            } else {
                MeetingRecordingView(model: model, actions: actions)
            }
        }
        .frame(width: 920, height: 620)
    }
}

// MARK: - Chooser

private struct MeetingChooserView: View {
    @Bindable var model: MeetingWindowModel
    let actions: MeetingActions

    private var chooser: MeetingWindowModel.Chooser { model.chooser }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start a meeting").font(.title2.weight(.semibold))
            Text(
                "Mini Whisper transcribes the meeting live with speaker labels, keeps your typed notes"
                    + " beside it, and writes a summary when you stop."
            )
            .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                card(.remote)
                card(.inRoom)
            }
            if chooser.showsSystemAudioNote(for: model.mode) {
                Label(MeetingWindowModel.Chooser.systemAudioNote, systemImage: "info.circle")
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
            }
            Spacer()
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            HStack {
                if let reason = chooser.startBlockedReason {
                    Text(reason).foregroundStyle(.secondary)
                } else if let engine = chooser.engineLine {
                    HStack(spacing: 0) {
                        Text("\(engine) · change under ")
                        Button("Settings → Meetings", action: actions.openSettings).buttonStyle(.link)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: actions.cancel).keyboardShortcut(.cancelAction)
                Button("Start", action: actions.start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStart)
            }
        }
        .padding(28)
    }

    private func card(_ mode: MeetingMode) -> some View {
        let unavailable = mode == .remote ? chooser.remoteUnavailableReason : nil
        let selected = model.mode == mode
        return Button {
            model.mode = mode
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(MeetingWindowModel.title(of: mode)).font(.headline)
                    Spacer()
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                }
                Text(chooser.description(of: mode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let text = unavailable ?? chooser.priceLabel {
                    Text(text).font(.caption)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(unavailable != nil)
        .opacity(unavailable == nil ? 1 : 0.5)
    }
}

// MARK: - Recording

private struct MeetingRecordingView: View {
    let model: MeetingWindowModel
    let actions: MeetingActions

    private var canPauseOrStop: Bool {
        if case .paused = model.state { return true }
        return model.state == .recording
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = model.errorMessage {
                Banner(text: error, symbol: "exclamationmark.triangle", color: .red)
            }
            if let hint = model.silenceHint {
                Banner(text: hint, symbol: "speaker.slash", color: .orange) {
                    Button("Open Privacy Settings…") {
                        NSWorkspace.shared.open(MeetingWindowModel.privacySettingsURL)
                    }
                }
            }
            HStack(spacing: 0) {
                TranscriptView(model: model, actions: actions)
                Divider()
                NotesPane(model: model, actions: actions).frame(width: 280)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(model.title.isEmpty ? "Starting…" : model.title).font(.headline).lineLimit(1)
            Chip(text: MeetingWindowModel.title(of: model.mode))
            Chip(text: model.captureChip, dot: model.state == .recording ? .green : .secondary)
            if let connection = model.connectionChip {
                Chip(text: connection, dot: .orange)
            }
            Spacer()
            Text(model.elapsedText).bold().monospacedDigit()
            (Text(model.costText).bold() + Text(model.state == .stopped ? " total" : " so far")).monospacedDigit()
            if model.state != .stopped {
                Button(model.pauseTitle, action: actions.pauseOrResume).disabled(!canPauseOrStop)
                Button("Stop", action: actions.stop).disabled(!canPauseOrStop)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct TranscriptView: View {
    let model: MeetingWindowModel
    let actions: MeetingActions

    private struct Renaming: Equatable {
        var paragraph: UUID
        var speaker: Int
    }

    private struct PendingMerge {
        var speaker: Int
        var name: String
        var prompt: String
    }

    private static let bottom = "bottom"
    private static let palette = [
        Color(red: 0.42, green: 0.25, blue: 0.71),
        Color(red: 0.10, green: 0.50, blue: 0.56),
        Color(red: 0.70, green: 0.40, blue: 0.11),
    ]

    @State private var renaming: Renaming?
    @State private var renameDraft = ""
    @State private var pendingMerge: PendingMerge?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let source = model.sourceLine {
                        Text(source).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.rows) { row in
                        rowView(row)
                    }
                    if let partial = model.partial {
                        partialView(partial)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.rows.count) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: model.partial) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
        }
        .alert(
            pendingMerge?.prompt ?? "",
            isPresented: Binding(get: { pendingMerge != nil }, set: { if !$0 { pendingMerge = nil } })
        ) {
            Button("Merge") {
                if let merge = pendingMerge { actions.rename(merge.speaker, merge.name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private func rowView(_ row: MeetingWindowModel.TranscriptRow) -> some View {
        switch row {
        case .paragraph(let paragraph):
            paragraphView(paragraph)
        case .note:
            MarkerLine(text: row.text, symbol: "note.text", color: .accentColor)
        case .marker(let marker):
            MarkerLine(
                text: row.text,
                symbol: marker.kind == .gap ? "exclamationmark.triangle" : "pause.circle",
                color: marker.kind == .gap ? .orange : .secondary
            )
        }
    }

    private func paragraphView(_ paragraph: MeetingWindowModel.Paragraph) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Button(model.name(of: paragraph.speaker)) {
                    renameDraft = model.name(of: paragraph.speaker)
                    renaming = Renaming(paragraph: paragraph.id, speaker: paragraph.speaker)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color(of: paragraph.speaker))
                .popover(isPresented: Binding(
                    get: { renaming?.paragraph == paragraph.id },
                    set: { if !$0 { renaming = nil } }
                )) {
                    renamePopover(speaker: paragraph.speaker)
                }
                Text(paragraph.time).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(paragraph.text).textSelection(.enabled)
        }
    }

    private func partialView(_ partial: MeetingWindowModel.Partial) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let header = partial.header {
                Text(header).font(.system(size: 13, weight: .semibold))
            }
            Text(partial.text).foregroundColor(.secondary) + Text(" ▍").foregroundColor(.accentColor)
        }
    }

    private func renamePopover(speaker: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.renameTitle(of: speaker)).font(.caption).foregroundStyle(.secondary)
            TextField("Name", text: $renameDraft)
                .frame(width: 220)
                .onSubmit { commitRename(speaker: speaker) }
            HStack {
                Spacer()
                Button("Cancel") { renaming = nil }
                Button("Rename") { commitRename(speaker: speaker) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    /// §5.7 Rename to an existing name: the merge is confirmed first.
    private func commitRename(speaker: Int) {
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty else { return }
        if let prompt = model.mergePrompt(renaming: speaker, to: name) {
            pendingMerge = PendingMerge(speaker: speaker, name: name, prompt: prompt)
        } else {
            actions.rename(speaker, name)
        }
    }

    private func color(of speaker: Int) -> Color {
        speaker == SpeakerRegistry.userID ? .accentColor : Self.palette[abs(speaker - 1) % Self.palette.count]
    }
}

// MARK: - Notes

private struct NotesPane: View {
    @Bindable var model: MeetingWindowModel
    let actions: MeetingActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOTES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.notes) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(MeetingWindowModel.time(of: note))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(note.text).font(.callout).textSelection(.enabled)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.state.isActive {
                Divider()
                composer
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 5) {
            NoteEditor(text: $model.noteDraft) {
                if let note = model.commitNote() { actions.addNote(note) }
            }
            .frame(height: 56)
            .overlay(alignment: .topLeading) {
                if model.noteDraft.isEmpty {
                    Text("Type a note…").foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor)))
            Text("Enter adds the note · Shift+Enter for a new line").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

/// R8: Enter commits the note, Shift+Enter inserts a newline. An `NSTextView`, because its
/// `insertNewline:` command is where the two can be told apart.
private struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            textView.isRichText = false
            textView.allowsUndo = true
            textView.drawsBackground = false
            textView.font = .systemFont(ofSize: 12)
            textView.textContainerInset = NSSize(width: 4, height: 6)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let textView = scrollView.documentView as? NSTextView, textView.string != text {
            textView.string = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor

        init(_ parent: NoteEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onCommit()
            }
            return true
        }
    }
}

// MARK: - Pieces

private struct Chip: View {
    let text: String
    var dot: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .overlay(Capsule().stroke(Color(nsColor: .separatorColor)))
    }
}

/// A note or marker between paragraphs, centred between two dashed rules.
private struct MarkerLine: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            rule
            Label(text, systemImage: symbol).font(.system(size: 11.5)).foregroundStyle(color).layoutPriority(1)
            rule
        }
    }

    private var rule: some View {
        Rule().stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(minWidth: 12, maxHeight: 1)
    }

    private struct Rule: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: 0, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

private struct Banner<Accessory: View>: View {
    let text: String
    let symbol: String
    let color: Color
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack {
            Label(text, systemImage: symbol).foregroundStyle(color)
            Spacer()
            accessory
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
    }
}

extension Banner where Accessory == EmptyView {
    init(text: String, symbol: String, color: Color) {
        self.init(text: text, symbol: symbol, color: color) { EmptyView() }
    }
}
