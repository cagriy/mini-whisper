import AppKit
import MWMeetings
import SwiftUI

/// The live meeting's notes beside the transcript, with the composer while it records (R8).
struct NotesPane: View {
    @Bindable var model: MeetingWindowModel
    let actions: MeetingActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Notes", trailing: model.notes.isEmpty ? nil : "\(model.notes.count)")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.s5) {
                    ForEach(model.notes) { note in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                            Text(MeetingWindowModel.time(of: note))
                                .textStyle(.meta)
                                .monospacedDigit()
                                .foregroundStyle(DS.Colors.textTertiary)
                            Text(note.text)
                                .textStyle(.body)
                                .foregroundStyle(DS.Colors.text)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s7)
                .padding(.vertical, DS.Space.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.state.isActive {
                composer
            }
        }
        .sidePane()
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            NoteEditor(text: $model.noteDraft) {
                if let note = model.commitNote() { actions.addNote(note) }
            }
            .frame(height: 60)
            .overlay(alignment: .topLeading) {
                if model.noteDraft.isEmpty {
                    Text("Type a note…")
                        .textStyle(.body)
                        .foregroundStyle(DS.Colors.textTertiary)
                        .padding(.horizontal, DS.Space.s5)
                        .padding(.vertical, DS.Space.s3)
                        .allowsHitTesting(false)
                }
            }
            .modifier(FieldChrome(
                shape: RoundedRectangle(cornerRadius: DS.Radius.field), fill: DS.Colors.canvas, focused: false
            ))
            Text("Enter adds the note · Shift+Enter for a new line")
                .textStyle(.meta)
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .padding(.horizontal, DS.Space.s7)
        .padding(.top, DS.Space.s6 + DS.Size.hairline)
        .padding(.bottom, DS.Space.s6)
        .hairline(.top)
    }
}

/// The finished meeting's Notes tab: the notes by time, read-only.
struct NotesList: View {
    let notes: [Note]

    var body: some View {
        if notes.isEmpty {
            Text("No notes.").textStyle(.body).foregroundStyle(DS.Colors.textSecondary)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(notes) { note in
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s5) {
                        Text(MeetingWindowModel.time(of: note))
                            .textStyle(.meta)
                            .monospacedDigit()
                            .foregroundStyle(DS.Colors.textTertiary)
                            .frame(width: 64, alignment: .leading)
                        Text(note.text)
                            .textStyle(.transcript)
                            .foregroundStyle(DS.Colors.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, DS.Space.s4 + DS.Size.hairline)
                    .padding(.bottom, DS.Space.s4)
                    .hairline(.top)
                }
            }
            .frame(maxWidth: DS.Size.readingColumn, alignment: .leading)
        }
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
            textView.font = DS.TextStyle.body.nsFont
            textView.textColor = DS.Colors.text.nsColor
            // Level with the placeholder: the container adds its own padding to the inset.
            let padding = textView.textContainer?.lineFragmentPadding ?? 0
            textView.textContainerInset = NSSize(width: DS.Space.s5 - padding, height: DS.Space.s3)
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
