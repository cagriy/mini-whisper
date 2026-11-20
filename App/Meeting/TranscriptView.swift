import MWMeetings
import SwiftUI

/// A meeting's transcript: paragraphs with their speakers, note and marker lines and the words
/// still arriving. After Stop a paragraph is edited by double-click, its segments moved from its
/// menu, and a speaker renamed from the name (R13). A remembered voice's suggestion shows as a
/// provisional name with Accept, Edit and Dismiss, and an applied name offers "Not <name>"
/// (design v8 §5 UI surfaces).
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
    /// The paragraph under the pointer, and the one whose "Not <name>" has keyboard focus.
    @State private var hovered: UUID?
    @FocusState private var focusedReject: UUID?
    /// The column is too narrow for a suggestion's actions beside its name.
    @State private var narrow = false

    private static let bottom = "bottom"
    /// Below this transcript width a suggestion's actions take their own line.
    private nonisolated static let narrowWidth: CGFloat = 470
    private static let popoverWidth: CGFloat = 220

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
        .onGeometryChange(for: Bool.self) { $0.size.width < Self.narrowWidth } action: { narrow = $0 }
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
            header(paragraph, model.nameState(of: paragraph))
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
        .onHover { inside in
            if inside {
                hovered = paragraph.id
            } else if hovered == paragraph.id {
                hovered = nil
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if model.canEdit, editing != paragraph.id { beginEditing(paragraph) }
        })
        .contextMenu {
            if model.canEdit { segmentMenu(paragraph) }
        }
    }

    /// A suggestion's actions sit at the right of the name, or under it in a narrow column.
    @ViewBuilder private func header(
        _ paragraph: MeetingWindowModel.Paragraph, _ state: MeetingWindowModel.NameState
    ) -> some View {
        if case .suggested(let match) = state, narrow {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                nameLine(paragraph, state)
                suggestionActions(match, of: paragraph)
                    .padding(.bottom, DS.Space.s2)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                nameLine(paragraph, state)
                switch state {
                case .suggested(let match):
                    Spacer(minLength: DS.Space.s4)
                    suggestionActions(match, of: paragraph).besideName()
                case .applied(let match):
                    rejectAction(match, of: paragraph).besideName()
                case .plain:
                    EmptyView()
                }
            }
        }
    }

    /// The speaker's name, or a suggestion's provisional name, then the paragraph's time.
    private func nameLine(
        _ paragraph: MeetingWindowModel.Paragraph, _ state: MeetingWindowModel.NameState
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
            Group {
                if case .suggested(let match) = state {
                    ProvisionalName(
                        name: match.name, current: model.name(of: paragraph.speaker),
                        color: SpeakerColor.of(paragraph.speaker)
                    ) { beginRenaming(paragraph) }
                } else {
                    Button(model.name(of: paragraph.speaker)) { beginRenaming(paragraph) }
                        .buttonStyle(.plain)
                        .textStyle(.body.weight(.semibold))
                        .foregroundStyle(SpeakerColor.of(paragraph.speaker))
                }
            }
            .popover(isPresented: Binding(
                get: { renaming == paragraph.id },
                set: { if !$0 { renaming = nil } }
            )) {
                renamePopover(paragraph)
            }
            Text(paragraph.time).textStyle(.meta).monospacedDigit().foregroundStyle(DS.Colors.textTertiary)
        }
    }

    /// R15: Edit opens the rename popover on the suggested name.
    private func suggestionActions(_ match: NameMatch, of paragraph: MeetingWindowModel.Paragraph) -> some View {
        HStack(spacing: DS.Space.s3) {
            Button("Accept") { actions.acceptSuggestion(match.key) }
            Button("Edit") { beginRenaming(paragraph) }
            Button("Dismiss") { actions.dismissSuggestion(match.key) }
        }
        .buttonStyle(.pill(.quietAction, size: .small))
        .fixedSize()
    }

    /// Kept in the layout when hidden, so hovering never moves the header.
    private func rejectAction(_ match: NameMatch, of paragraph: MeetingWindowModel.Paragraph) -> some View {
        let shown = hovered == paragraph.id || focusedReject == paragraph.id
        return Button(model.rejectTitle(of: paragraph)) { actions.rejectMatch(match.key) }
            .buttonStyle(.pill(.quietAction, size: .small))
            .focused($focusedReject, equals: paragraph.id)
            .fixedSize()
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
    }

    private func beginRenaming(_ paragraph: MeetingWindowModel.Paragraph) {
        renameDraft = model.renameDraft(of: paragraph)
        renaming = paragraph.id
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
        Button("Rename “\(model.name(of: paragraph.speaker))”…") { beginRenaming(paragraph) }
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

    private func renamePopover(_ paragraph: MeetingWindowModel.Paragraph) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(model.renameTitle(of: paragraph)).textStyle(.meta).foregroundStyle(DS.Colors.textSecondary)
            TextField("Name", text: $renameDraft)
                .dsField()
                .frame(width: Self.popoverWidth)
                .onSubmit { commitRename(paragraph) }
            if let line = model.rememberLine(speaker: paragraph.speaker, draft: renameDraft) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                    Image(systemName: "waveform").foregroundStyle(DS.Colors.accent)
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
                .textStyle(.meta)
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(width: Self.popoverWidth, alignment: .leading)
            }
            HStack(spacing: DS.Space.s4) {
                Spacer(minLength: 0)
                Button("Cancel") { renaming = nil }.buttonStyle(.pill(size: .small))
                Button("Rename") { commitRename(paragraph) }
                    .buttonStyle(.pill(.primary, size: .small))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.s6)
    }

    /// §5.7 Rename to an existing name: the merge is confirmed first. Naming a suggestion asks
    /// nothing, and its suggested name unchanged accepts it (design v8 R15).
    private func commitRename(_ paragraph: MeetingWindowModel.Paragraph) {
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let speaker = paragraph.speaker
        renaming = nil
        guard !name.isEmpty else { return }
        if case .suggested(let match) = model.nameState(of: paragraph) {
            if name == match.name {
                actions.acceptSuggestion(match.key)
            } else {
                actions.rename(speaker, name)
            }
        } else if let prompt = model.mergePrompt(renaming: speaker, to: name) {
            let rename = actions.rename
            dialog = PageDialog(title: prompt, confirmTitle: "Merge") { rename(speaker, name) }
        } else {
            actions.rename(speaker, name)
        }
    }
}

private extension View {
    /// A small pill beside a speaker's name adds no height to the name's line, so a paragraph with
    /// one is spaced as one without.
    func besideName() -> some View {
        padding(.vertical, (DS.TextStyle.body.lineHeight - DS.Size.controlSmall) / 2)
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
        HorizontalRule().stroke(DS.Colors.line, style: StrokeStyle(lineWidth: DS.Size.hairline, dash: [3, 3]))
            .frame(minWidth: 12, maxHeight: 1)
    }
}
