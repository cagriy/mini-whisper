import SwiftUI

/// The meeting page (design §5.9): the chooser until Start, the live meeting while it runs, then
/// the finished meeting.
struct MeetingPage: View {
    let model: MeetingWindowModel
    let actions: MeetingActions
    /// The back pill's text: the page this one was opened from.
    let backLabel: String
    @Binding var dialog: PageDialog?

    var body: some View {
        Group {
            switch model.state {
            case .idle: ChooserPage(model: model, actions: actions)
            case .stopped: FinishedPage(model: model, actions: actions, backLabel: backLabel, dialog: $dialog)
            default: LivePage(model: model, actions: actions, dialog: $dialog)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colors.canvas)
    }
}

/// A confirmation a meeting page asks for, drawn as a `DSDialog` over the whole window.
struct PageDialog {
    let title: String
    var message: String?
    /// The filled button's title.
    let confirmTitle: String
    let confirm: @MainActor () -> Void
}

/// The bar above a page that has a back pill.
struct TopBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: DS.Space.s4) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, DS.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.canvas)
    }
}

/// R15: a meeting's title, renamed in place.
struct TitleField: View {
    let model: MeetingWindowModel
    let style: DS.TextStyle
    /// Nil lets a long title wrap.
    var lineLimit: Int? = 1
    let retitle: @MainActor (String) -> Void

    @State private var draft = TitleDraft()
    @FocusState private var focused: Bool

    var body: some View {
        if draft.isEditing {
            TextField("Title", text: $draft.text)
                .textFieldStyle(.plain)
                .textStyle(style)
                .foregroundStyle(DS.Colors.text)
                .focused($focused)
                .onAppear { focused = true }
                .onSubmit(commit)
                .onExitCommand { draft.cancel() }
                .onChange(of: focused) { if !focused { commit() } }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                Text(model.title.isEmpty ? "Starting…" : model.title)
                    .textStyle(style)
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(lineLimit)
                    .accessibilityAddTraits(.isHeader)
                if !model.title.isEmpty {
                    Button {
                        draft.begin(model.title)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .font(DS.TextStyle.body.font)
                    .foregroundStyle(DS.Colors.textTertiary)
                    .help("Rename the meeting")
                }
            }
        }
    }

    private func commit() {
        if let title = draft.commit() { retitle(title) }
    }
}

/// A title being renamed in place. `text` is not optional: a binding that force-unwraps an
/// optional traps when the field reads it after the edit ends, before SwiftUI removes the field.
struct TitleDraft {
    private(set) var isEditing = false
    var text = ""

    mutating func begin(_ title: String) {
        text = title
        isEditing = true
    }

    /// The edited title, once; the focus loss that follows Return finds nothing to commit.
    mutating func commit() -> String? {
        guard isEditing else { return nil }
        isEditing = false
        return text
    }

    mutating func cancel() {
        isEditing = false
    }
}
