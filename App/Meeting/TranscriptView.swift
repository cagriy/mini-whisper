import MWMeetings
import SwiftUI

/// A meeting's transcript: paragraphs with their speakers, note and marker lines and the words
/// still arriving. After Stop a paragraph is edited by double-click, its segments moved from its
/// menu, and a speaker renamed from the name (R13).
struct TranscriptView: View {
    let model: MeetingWindowModel
    let actions: MeetingActions
    /// The merge confirmation, drawn over the window.
    @Binding var dialog: PageDialog?
    /// In a scroll view of its own, following the last words and an opened score line; otherwise
    /// laid out in the page's.
    var scrolls = true

    /// The paragraph whose speaker popover is open.
    @State private var renaming: UUID?
    @State private var renameDraft = ""
    /// The paragraph being edited, and its segments' texts (R13).
    @State private var editing: UUID?
    @State private var drafts: [MeetingWindowModel.SegmentEdit] = []
    @FocusState private var focusedDraft: UUID?

    private static let bottom = "bottom"

    var body: some View {
        if scrolls {
            ScrollViewReader { proxy in
                ScrollView {
                    content
                        .padding(.horizontal, DS.Space.s9)
                        .padding(.vertical, 20)
                }
                // A live meeting follows its last words.
                .onChange(of: model.rows.count) {
                    if model.state != .stopped { proxy.scrollTo(Self.bottom, anchor: .bottom) }
                }
                .onChange(of: model.partial) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
                // An opened score line brings its words into view.
                .onChange(of: model.testCall?.expanded) {
                    let highlighted = model.highlightedParagraphs
                    guard let row = model.rows.first(where: { $0.paragraph.map { highlighted.contains($0.id) } ?? false })
                    else { return }
                    withAnimation { proxy.scrollTo(row.id, anchor: .center) }
                }
            }
        } else {
            content
        }
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let source = model.sourceLine {
                Text(source)
                    .textStyle(.meta)
                    .foregroundStyle(DS.Colors.textTertiary)
                    .padding(.bottom, DS.Space.s7)
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
        .frame(maxWidth: DS.Size.readingColumn, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func rowView(_ row: MeetingWindowModel.TranscriptRow, highlighted: Set<UUID>) -> some View {
        switch row {
        case .paragraph(let paragraph):
            paragraphView(paragraph)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if highlighted.contains(paragraph.id) {
                        RoundedRectangle(cornerRadius: DS.Radius.field)
                            .fill(DS.Colors.accentSoft)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.field).strokeBorder(DS.Colors.accent))
                            .padding(.horizontal, -DS.Space.s4)
                            .padding(.vertical, -DS.Space.s3)
                    }
                }
                .padding(.bottom, DS.Space.s7)
        case .note:
            MarkerLine(text: row.text, symbol: "note.text", color: DS.Colors.textTertiary)
        case .marker(let marker):
            MarkerLine(
                text: row.text,
                symbol: marker.kind == .gap ? "exclamationmark.triangle" : "pause.circle",
                color: marker.kind == .gap ? DS.Colors.warn : DS.Colors.textTertiary
            )
        }
    }

    private func paragraphView(_ paragraph: MeetingWindowModel.Paragraph) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                Button(model.name(of: paragraph.speaker)) {
                    renameDraft = model.name(of: paragraph.speaker)
                    renaming = paragraph.id
                }
                .buttonStyle(.plain)
                .textStyle(.body.weight(.semibold))
                .foregroundStyle(SpeakerColor.of(paragraph.speaker))
                .popover(isPresented: Binding(
                    get: { renaming == paragraph.id },
                    set: { if !$0 { renaming = nil } }
                )) {
                    renamePopover(speaker: paragraph.speaker)
                }
                Text(paragraph.time).textStyle(.meta).monospacedDigit().foregroundStyle(DS.Colors.textTertiary)
            }
            if editing == paragraph.id {
                editor
            } else {
                Text(paragraph.text)
                    .textStyle(.transcript)
                    .foregroundStyle(DS.Colors.text)
                    .textSelection(.enabled)
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
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            ForEach($drafts, id: \.segment) { $draft in
                TextField("", text: $draft.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .textStyle(.transcript)
                    .foregroundStyle(DS.Colors.text)
                    .focused($focusedDraft, equals: draft.segment)
                    .padding(.horizontal, DS.Space.s5 + DS.Size.hairline)
                    .padding(.vertical, DS.Space.s3)
                    .modifier(FieldChrome(
                        shape: RoundedRectangle(cornerRadius: DS.Radius.field), fill: DS.Colors.canvas,
                        focused: focusedDraft == draft.segment
                    ))
            }
            HStack(spacing: DS.Space.s4) {
                Spacer(minLength: 0)
                Button("Cancel") { editing = nil }
                    .buttonStyle(.pill(size: .small))
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    for edit in model.edits(drafts) { actions.edit(edit.segment, edit.text) }
                    editing = nil
                }
                .buttonStyle(.pill(.primary, size: .small))
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
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if let header = partial.header {
                Text(header)
                    .textStyle(.body.weight(.semibold))
                    .foregroundStyle(model.partialSpeaker.map(SpeakerColor.of) ?? DS.Colors.text)
            }
            (Text(partial.text).foregroundStyle(DS.Colors.textTertiary) + Text(" ▍").foregroundStyle(DS.Colors.accent))
                .textStyle(.transcript)
        }
        .padding(.bottom, DS.Space.s7)
    }

    private func renamePopover(speaker: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(model.renameTitle(of: speaker)).textStyle(.meta).foregroundStyle(DS.Colors.textSecondary)
            TextField("Name", text: $renameDraft)
                .dsField()
                .frame(width: 220)
                .onSubmit { commitRename(speaker: speaker) }
            HStack(spacing: DS.Space.s4) {
                Spacer(minLength: 0)
                Button("Cancel") { renaming = nil }.buttonStyle(.pill(size: .small))
                Button("Rename") { commitRename(speaker: speaker) }
                    .buttonStyle(.pill(.primary, size: .small))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.s6)
    }

    /// §5.7 Rename to an existing name: the merge is confirmed first.
    private func commitRename(speaker: Int) {
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty else { return }
        if let prompt = model.mergePrompt(renaming: speaker, to: name) {
            let rename = actions.rename
            dialog = PageDialog(title: prompt, confirmTitle: "Merge") { rename(speaker, name) }
        } else {
            actions.rename(speaker, name)
        }
    }
}

/// A note or marker between paragraphs, centred between two dashed rules.
private struct MarkerLine: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: DS.Space.s5) {
            rule
            Label(text, systemImage: symbol)
                .textStyle(.meta)
                .foregroundStyle(color)
                .layoutPriority(1)
            rule
        }
        .padding(.top, DS.Space.s2)
        .padding(.bottom, DS.Space.s7)
    }

    private var rule: some View {
        Rule().stroke(DS.Colors.line, style: StrokeStyle(lineWidth: DS.Size.hairline, dash: [3, 3]))
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
