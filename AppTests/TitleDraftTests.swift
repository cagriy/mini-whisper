import Testing
@testable import MiniWhisper

/// A meeting title renamed in place (R15). The field's text is never optional, so its binding
/// stays readable while SwiftUI removes the field after an edit ends.
@Suite struct TitleDraftTests {
    @Test func commitReturnsTheEditedTitleAndEndsEditing() {
        var draft = TitleDraft()
        draft.begin("Standup")
        draft.text = "Planning"

        #expect(draft.commit() == "Planning")
        #expect(!draft.isEditing)
    }

    @Test func focusLossAfterReturnCommitsNothing() {
        var draft = TitleDraft()
        draft.begin("Standup")
        _ = draft.commit()

        #expect(draft.commit() == nil)
    }

    @Test func escapeDiscardsTheEdit() {
        var draft = TitleDraft()
        draft.begin("Standup")
        draft.text = "Planning"
        draft.cancel()

        #expect(draft.commit() == nil)
        #expect(!draft.isEditing)
    }

    @Test func textStaysReadableAfterEditingEnds() {
        var draft = TitleDraft()
        draft.begin("Standup")
        _ = draft.commit()

        #expect(draft.text == "Standup")
    }
}
