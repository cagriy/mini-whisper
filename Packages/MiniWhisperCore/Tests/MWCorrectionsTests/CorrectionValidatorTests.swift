import MWConfig
import Testing

import MWCorrections

/// R5 and the §5.5 messages.
@Suite struct CorrectionValidatorTests {
    private static let slack = "com.tinyspeck.slackmacgap"

    private static let existing = [
        CorrectionRule(id: "slack", heard: "eefa", write: "Aoife", bundleID: slack),
        CorrectionRule(id: "global", heard: "get hub", write: "GitHub"),
    ]

    private func validate(
        heard: String,
        write: String,
        bundleID: String? = nil,
        id: String = "draft",
        excluding: String? = nil,
        scopeName: String? = nil
    ) -> CorrectionValidator.ValidationError? {
        CorrectionValidator.validate(
            CorrectionRule(id: id, heard: heard, write: write, bundleID: bundleID),
            against: Self.existing,
            excluding: excluding,
            scopeName: scopeName
        )
    }

    @Test func emptyHeardIsRejected() {
        let error = validate(heard: "  ", write: "Aoife")

        #expect(error == .emptyHeard)
        #expect(error?.message == "Select the misheard phrase first.")
    }

    @Test func emptyWriteIsRejected() {
        let error = validate(heard: "eefa", write: " \n ")

        #expect(error == .emptyWrite)
        #expect(error?.message == "Enter the spelling to write.")
    }

    @Test func aWriteIdenticalToHeardIsRejected() {
        let error = validate(heard: "eefa", write: "eefa")

        #expect(error == .noChange)
        #expect(error?.message == "Nothing to remember — Write is the same as Heard.")
    }

    @Test func aCaseOnlyFixIsAllowed() {
        #expect(validate(heard: "github", write: "GitHub") == nil)
    }

    @Test func aPhraseAlreadyRememberedInTheSameScopeIsRejected() {
        let error = validate(heard: "Eefa", write: "Aoifé", bundleID: Self.slack, scopeName: "Slack")

        #expect(error == .duplicate(heard: "Eefa", existingWrite: "Aoife", scope: "Slack"))
        #expect(error?.message == "‘Eefa’ is already remembered for Slack as ‘Aoife’.")
    }

    @Test func theSamePhraseInAnotherScopeIsAllowed() {
        #expect(validate(heard: "eefa", write: "Eva") == nil)
        #expect(validate(heard: "get hub", write: "GitHub Inc", bundleID: Self.slack) == nil)
    }

    @Test func withoutAScopeNameTheDuplicateMessageNamesTheScopeItself() {
        #expect(
            validate(heard: "get hub", write: "GitHub Inc")?.message
                == "‘get hub’ is already remembered for All apps as ‘GitHub’."
        )
        #expect(
            validate(heard: "eefa", write: "Eve", bundleID: Self.slack)?.message
                == "‘eefa’ is already remembered for \(Self.slack) as ‘Aoife’."
        )
    }

    @Test func editingARuleInPlaceExcludesItself() {
        #expect(validate(heard: "eefa", write: "Aoife Byrne", bundleID: Self.slack, excluding: "slack") == nil)
    }
}
