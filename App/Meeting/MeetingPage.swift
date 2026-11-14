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

    /// Non-nil while editing.
    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        if let text = Binding($draft) {
            TextField("Title", text: text)
                .textFieldStyle(.plain)
                .textStyle(style)
                .foregroundStyle(DS.Colors.text)
                .focused($focused)
                .onAppear { focused = true }
                .onSubmit(commit)
                .onExitCommand { draft = nil }
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
                        draft = model.title
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
        if let draft { retitle(draft) }
        draft = nil
    }
}
