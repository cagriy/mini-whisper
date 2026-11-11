import AppKit
import MWMeetingPipeline
import MWMeetings
import SwiftUI

/// The meeting window: the chooser until Start, the live transcript with the notes pane, then
/// the stopped meeting with its summary (accepted mockup `mockup-v4-meeting-window.html`).
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
                if let testCall = model.testCall {
                    Group {
                        if testCall.score == nil {
                            ScriptPane(model: testCall, skip: actions.skipLine)
                        } else {
                            ScorePane(model: testCall) { await model.loadEarlierRuns() }
                        }
                    }
                    .frame(width: 310)
                } else {
                    NotesPane(model: model, actions: actions).frame(width: 280)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            TitleField(model: model, retitle: actions.retitle)
            if model.isTest {
                TestTag()
            } else {
                Chip(text: MeetingWindowModel.title(of: model.mode))
            }
            if let ended = model.endedChip {
                Chip(text: ended, dot: .secondary)
            } else {
                Chip(text: model.captureChip, dot: model.state == .recording ? .green : .secondary)
            }
            if let connection = model.connectionChip {
                Chip(text: connection, dot: .orange)
            }
            Spacer()
            Text(model.elapsedText).bold().monospacedDigit()
            (Text(model.costText).bold() + Text(model.state == .stopped ? " total" : " so far")).monospacedDigit()
            if model.state == .stopped {
                Menu("Export") {
                    Button("Export transcript…") { actions.export(.transcript) }
                    Button("Export summary…") { actions.export(.summary) }
                    Button("Export both…") { actions.export(.both) }
                }
                .fixedSize()
            } else {
                Button(model.pauseTitle, action: actions.pauseOrResume)
                    .disabled(!model.canPause)
                    .help(model.pauseHelp ?? "")
                Button("Stop", action: actions.stop).disabled(!model.canStop)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

/// R15: the header's title, renamed in place.
private struct TitleField: View {
    let model: MeetingWindowModel
    let retitle: @MainActor (String) -> Void

    /// Non-nil while editing.
    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        if let text = Binding($draft) {
            TextField("Title", text: text)
                .font(.headline)
                .frame(maxWidth: 360)
                .focused($focused)
                .onAppear { focused = true }
                .onSubmit(commit)
                .onExitCommand { draft = nil }
                .onChange(of: focused) { if !focused { commit() } }
        } else {
            HStack(spacing: 6) {
                Text(model.title.isEmpty ? "Starting…" : model.title).font(.headline).lineLimit(1)
                if !model.title.isEmpty {
                    Button {
                        draft = model.title
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Rename the meeting")
                }
            }
        }
    }

    private func commit() {
        if let draft { retitle(draft) }
        draft = nil
    }
}

/// R12: above the stopped transcript: the summary, its progress, or why there is none.
private struct SummaryPanelView: View {
    let panel: MeetingWindowModel.SummaryPanel
    let summarise: @MainActor () -> Void

    var body: some View {
        Group {
            switch panel {
            case .writing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Writing the summary…").foregroundStyle(.secondary)
                }
            case .message(let text, let canSummarise):
                HStack {
                    Text(text).foregroundStyle(.orange)
                    Spacer()
                    if canSummarise {
                        Button("Summarise", action: summarise)
                    }
                }
            case .ready(let sections, let meta):
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 28, alignment: .topLeading),
                                  GridItem(.flexible(), alignment: .topLeading)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: 4) {
                                if !section.title.isEmpty {
                                    Text(section.title.uppercased())
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text(Self.rendered(section.body))
                                    .font(.system(size: 12.5))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text(meta).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// Inline Markdown, bullets as "•". Links stay text: the summary is model output (§5.8).
    private static func rendered(_ body: String) -> AttributedString {
        var result = AttributedString()
        for (index, line) in body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            if index > 0 { result += AttributedString("\n") }
            var text = String(line)
            if let bullet = text.range(of: #"^\s*[-*] "#, options: .regularExpression) {
                text.replaceSubrange(bullet, with: "• ")
            }
            var markdown = (try? AttributedString(
                markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(text)
            for run in markdown.runs where run.link != nil { markdown[run.range].link = nil }
            result += markdown
        }
        return result
    }
}

private struct TranscriptView: View {
    let model: MeetingWindowModel
    let actions: MeetingActions

    private struct PendingMerge {
        var speaker: Int
        var name: String
        var prompt: String
    }

    private static let bottom = "bottom"

    /// The paragraph whose speaker popover is open.
    @State private var renaming: UUID?
    @State private var renameDraft = ""
    @State private var pendingMerge: PendingMerge?
    /// The paragraph being edited, and its segments' texts (R13).
    @State private var editing: UUID?
    @State private var drafts: [MeetingWindowModel.SegmentEdit] = []

    private static let top = "top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if let panel = model.summaryPanel {
                        SummaryPanelView(panel: panel, summarise: actions.summarise)
                        Divider()
                    }
                    transcript
                }
                .id(Self.top)
            }
            // A live meeting follows its last words; a stopped one opens on its summary.
            .onChange(of: model.rows.count) {
                if model.state != .stopped { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            }
            .onChange(of: model.partial) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: model.state) {
                if model.state == .stopped { proxy.scrollTo(Self.top, anchor: .top) }
            }
            // An opened score line brings its words into view.
            .onChange(of: model.testCall?.expanded) {
                let highlighted = model.highlightedParagraphs
                guard let row = model.rows.first(where: { $0.paragraph.map { highlighted.contains($0.id) } ?? false })
                else { return }
                withAnimation { proxy.scrollTo(row.id, anchor: .center) }
            }
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

    private var transcript: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if let source = model.sourceLine {
                Text(source).font(.caption).foregroundStyle(.secondary)
            }
            let highlighted = model.highlightedParagraphs
            ForEach(model.rows) { row in
                rowView(row, highlighted: highlighted)
            }
            if let partial = model.partial {
                partialView(partial)
            }
            Color.clear.frame(height: 1).id(Self.bottom)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func rowView(_ row: MeetingWindowModel.TranscriptRow, highlighted: Set<UUID>) -> some View {
        switch row {
        case .paragraph(let paragraph):
            paragraphView(paragraph)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if highlighted.contains(paragraph.id) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.2)))
                            .padding(.horizontal, -8)
                            .padding(.vertical, -6)
                    }
                }
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
                    renaming = paragraph.id
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SpeakerColor.of(paragraph.speaker))
                .popover(isPresented: Binding(
                    get: { renaming == paragraph.id },
                    set: { if !$0 { renaming = nil } }
                )) {
                    renamePopover(speaker: paragraph.speaker)
                }
                Text(paragraph.time).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            if editing == paragraph.id {
                editor
            } else {
                Text(paragraph.text).textSelection(.enabled)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if model.canEdit, editing != paragraph.id { beginEditing(paragraph) }
        })
        .contextMenu {
            if model.canEdit { segmentMenu(paragraph) }
        }
    }

    /// R13: one field per segment, so each keeps its own times.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($drafts, id: \.segment) { $draft in
                TextField("", text: $draft.text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") { editing = nil }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    for edit in model.edits(drafts) { actions.edit(edit.segment, edit.text) }
                    editing = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func beginEditing(_ paragraph: MeetingWindowModel.Paragraph) {
        drafts = model.segments(in: paragraph).map { .init(segment: $0.id, text: $0.text) }
        editing = paragraph.id
    }

    /// R13: *Move this segment to*; a merged paragraph lists its segments by time.
    @ViewBuilder private func segmentMenu(_ paragraph: MeetingWindowModel.Paragraph) -> some View {
        let segments = model.segments(in: paragraph)
        if segments.count == 1, let segment = segments.first {
            Section("Move this segment to") { choices(for: segment.id) }
        } else {
            ForEach(segments) { segment in
                let excerpt = segment.text.count > 40 ? segment.text.prefix(40) + "…" : segment.text
                Menu("Move \(MeetingTime.format(segment.start)) · \(excerpt)") {
                    choices(for: segment.id)
                }
            }
        }
        Divider()
        Button("Rename “\(model.name(of: paragraph.speaker))”…") {
            renameDraft = model.name(of: paragraph.speaker)
            renaming = paragraph.id
        }
    }

    private func choices(for segment: UUID) -> some View {
        ForEach(model.reassignChoices(for: segment)) { choice in
            Toggle(choice.name, isOn: Binding(
                get: { choice.isCurrent },
                set: { _ in if !choice.isCurrent { actions.reassign(segment, choice.id) } }
            ))
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
}

// MARK: - Notes

private struct NotesPane: View {
    @Bindable var model: MeetingWindowModel
    let actions: MeetingActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Notes")
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

/// Speaker colours: the user in the accent colour, others by their label.
enum SpeakerColor {
    static let palette = [
        Color(red: 0.42, green: 0.25, blue: 0.71),
        Color(red: 0.10, green: 0.50, blue: 0.56),
        Color(red: 0.70, green: 0.40, blue: 0.11),
    ]

    static func of(_ speaker: Int) -> Color {
        speaker == SpeakerRegistry.userID ? .accentColor : palette[abs(speaker - 1) % palette.count]
    }
}

/// A side pane's small-caps title, with an optional figure at the right.
struct PaneHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
            Spacer(minLength: 8)
            if let trailing { Text(trailing.uppercased()).monospacedDigit() }
        }
        .lineLimit(1)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

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
