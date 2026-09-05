import Foundation
import MWConfig
import MWCorrections
import MWPaste
import MWPipeline
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct CorrectionModelTests {
    private final class RecordingPasteboard: PasteboardAccess, @unchecked Sendable {
        private(set) var written: [String] = []

        func snapshot() -> PasteboardSnapshot { PasteboardSnapshot(items: []) }
        func write(_ text: String) -> Int {
            written.append(text)
            return written.count
        }
        var changeCount: Int { written.count }
        func restore(_ snapshot: PasteboardSnapshot) {}
    }

    private static let transcript =
        "Can eefa review the release notes before Thursday, the get hub action is still red."

    private static func source(
        text: String = CorrectionModelTests.transcript,
        appName: String? = "Slack",
        bundleID: String? = "com.tinyspeck.slackmacgap",
        preselectAll: Bool = false
    ) -> CorrectionSource {
        CorrectionSource(
            text: text,
            appName: appName,
            bundleID: bundleID,
            engine: EngineName.openai.rawValue,
            deliveredAt: Date(timeIntervalSince1970: 1_757_088_420),
            preselectAll: preselectAll
        )
    }

    private struct Harness {
        let directory: URL
        let store: ConfigStore
        let pasteboard = RecordingPasteboard()
        let entries: [ImpactPreview.Entry]?

        /// `blocked` puts the config directory under a regular file, so every write throws.
        init(blocked: Bool = false, entries: [ImpactPreview.Entry]? = []) {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("mw-correction-\(UUID().uuidString)", isDirectory: true)
            if blocked {
                try? FileManager.default.createDirectory(
                    at: root.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                FileManager.default.createFile(atPath: root.path, contents: Data())
                directory = root.appendingPathComponent("config", isDirectory: true)
            } else {
                directory = root
            }
            store = ConfigStore(directory: directory)
            self.entries = entries
        }

        @MainActor
        func model(
            _ source: CorrectionSource = CorrectionModelTests.source(),
            config: Config = Config()
        ) -> CorrectionModel {
            CorrectionModel(
                source: source,
                config: config,
                deps: CorrectionModel.Dependencies(
                    store: store,
                    pasteboard: pasteboard,
                    historyEntries: { [entries] in entries }
                )
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        }
    }

    @MainActor
    private func select(_ model: CorrectionModel, _ substring: String) throws {
        let text = model.source.text
        let range = try #require(text.range(of: substring))
        model.select(NSRange(range, in: text))
    }

    // MARK: - Selection snapping (R29)

    @Test func selectionSnapsOutwardToWholeWords() throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()

        try select(model, "ef")

        #expect(model.heard == "eefa")
    }

    @Test func selectionWithSurroundingWhitespaceIsTrimmed() throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()

        try select(model, " get hub ")

        #expect(model.heard == "get hub")
    }

    @Test func whitespaceOnlySelectionLeavesHeardEmpty() throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        try select(model, "eefa")

        try select(model, " ")

        #expect(model.heard.isEmpty)
        #expect(model.write.isEmpty)
    }

    @Test func everySelectionResetsWriteAndSoundsLike() throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()

        try select(model, "eefa")
        model.write = "Aoife"
        model.soundsLike = "eefa, eva"
        try select(model, "get hub")

        #expect(model.heard == "get hub")
        #expect(model.write == "get hub")
        #expect(model.soundsLike == "get hub")
    }

    @Test func preselectAllTakesTheWholeTranscript() {
        let harness = Harness()
        defer { harness.cleanUp() }

        let model = harness.model(Self.source(
            text: "speech matics", appName: nil, bundleID: nil, preselectAll: true
        ))

        #expect(model.heard == "speech matics")
        #expect(model.write == "speech matics")
    }

    // MARK: - Sources

    @Test func sourcesCarryTheirOriginsFields() {
        let dictation = CorrectionSource(DeliveredDictation(
            text: "get hub",
            appName: "Slack",
            bundleID: "com.tinyspeck.slackmacgap",
            engine: .openai,
            deliveredAt: Date(timeIntervalSince1970: 1_757_088_420)
        ))
        #expect(dictation.text == "get hub")
        #expect(dictation.appName == "Slack")
        #expect(dictation.bundleID == "com.tinyspeck.slackmacgap")
        #expect(dictation.engine == "openai")
        #expect(!dictation.preselectAll)

        let phrase = CorrectionSource(phrase: "speech matics")
        #expect(phrase.text == "speech matics")
        #expect(phrase.bundleID == nil)
        #expect(phrase.preselectAll)
    }

    // MARK: - Scope (R30)

    @Test func scopeDefaultsToThisAppAndNamesIt() {
        let harness = Harness()
        defer { harness.cleanUp() }

        let model = harness.model()

        #expect(model.scope == .thisApp)
        #expect(model.canScopeToApp)
        #expect(model.thisAppLabel == "This app · Slack")
    }

    @Test func withoutABundleIDThisAppIsDisabledAndAllAppsSelected() {
        let harness = Harness()
        defer { harness.cleanUp() }

        let model = harness.model(Self.source(appName: nil, bundleID: nil))

        #expect(model.scope == .allApps)
        #expect(!model.canScopeToApp)
        #expect(model.thisAppLabel == "This app")
    }

    // MARK: - Preview and impact (R31)

    @Test func previewIsTheTranscriptWithTheDraftRuleApplied() throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()

        try select(model, "eefa")
        model.write = "Aoife"

        #expect(model.previewText == Self.transcript.replacingOccurrences(
            of: "eefa", with: "Aoife"
        ))
    }

    @Test func impactCountsOnlyEntriesInScopeAndKeepsThreeSnippets() async throws {
        let harness = Harness(entries: [
            ImpactPreview.Entry(text: "ask eefa about the retro", bundleID: "com.tinyspeck.slackmacgap"),
            ImpactPreview.Entry(text: "eefa owns the rota", bundleID: "com.tinyspeck.slackmacgap"),
            ImpactPreview.Entry(text: "ping Eefa about the invoice", bundleID: "com.tinyspeck.slackmacgap"),
            ImpactPreview.Entry(text: "eefa again", bundleID: "com.tinyspeck.slackmacgap"),
            ImpactPreview.Entry(text: "nothing here", bundleID: "com.tinyspeck.slackmacgap"),
            ImpactPreview.Entry(text: "eefa elsewhere", bundleID: "com.apple.Terminal"),
        ])
        defer { harness.cleanUp() }
        let model = harness.model()

        try select(model, "eefa")
        model.write = "Aoife"
        await model.settle()

        let impact = try #require(model.impact)
        #expect(impact.matching == 4)
        #expect(impact.total == 5)
        #expect(impact.snippets.count == 3)
        #expect(model.impactLine == "Would have changed 4 of 5 past dictations in Slack")
    }

    @Test func historyOffReadsTheFixedSentence() async throws {
        let harness = Harness(entries: nil)
        defer { harness.cleanUp() }
        let model = harness.model()

        try select(model, "eefa")
        model.write = "Aoife"
        await model.settle()

        #expect(model.impactLine == "History is off — no preview of past dictations.")
    }

    // MARK: - Copy, Save and the tally (R32)

    @Test func copyWritesThePreviewedTextAndPersistsOnlyTheTally() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        try select(model, "eefa")
        model.write = "Aoife"

        await model.copy()

        #expect(harness.pasteboard.written == [model.previewText])
        let config = await harness.store.load()
        #expect(config.corrections.isEmpty)
        #expect(config.correctionTally.map(\.heard) == ["eefa"])
        #expect(!model.saved)
    }

    @Test func editingWithoutCopyOrSaveWritesNothing() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()

        try select(model, "eefa")
        model.write = "Aoife"
        await model.settle()

        let config = await harness.store.load()
        #expect(config.corrections.isEmpty)
        #expect(config.correctionTally.isEmpty)
    }

    @Test func saveWithRememberOffIsDisabledAndPersistsNothing() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        try select(model, "eefa")
        model.write = "Aoife"
        model.remember = false

        #expect(!model.canSave)
        await model.save()

        #expect(!model.saved)
        #expect(await harness.store.load().corrections.isEmpty)
    }

    @Test func savePersistsOneRuleWithTheChosenScopeThenConfirms() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        try select(model, "eefa")
        model.write = "Aoife"
        model.soundsLike = "eefa, eva"

        await model.save()

        let rules = await harness.store.load().corrections
        #expect(rules.count == 1)
        #expect(rules.first?.heard == "eefa")
        #expect(rules.first?.write == "Aoife")
        #expect(rules.first?.soundsLike == ["eefa", "eva"])
        #expect(rules.first?.bundleID == "com.tinyspeck.slackmacgap")
        #expect(model.saved)
        #expect(model.confirmationTitle == "Remembered for Slack")
        #expect(model.confirmationDetail == """
            “eefa” will be written as “Aoife” in future dictations to Slack. \
            Edit or disable it any time under Settings → Vocabulary.
            """)
    }

    @Test func saveWithAllAppsScopeStoresNoBundleID() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        try select(model, "eefa")
        model.write = "Aoife"
        model.scope = .allApps

        await model.save()

        #expect(await harness.store.load().corrections.first?.bundleID == nil)
        #expect(model.confirmationTitle == "Remembered for All apps")
    }

    @Test func aFailedWriteShowsTheErrorKeepsTheDraftAndDoesNotConfirm() async throws {
        let harness = Harness(blocked: true)
        defer { harness.cleanUp() }
        let model = harness.model()
        try select(model, "eefa")
        model.write = "Aoife"

        await model.save()

        #expect(!model.saved)
        #expect(model.saveError?.isEmpty == false)
        #expect(model.heard == "eefa")
        #expect(model.write == "Aoife")
    }

    @Test func copyThenSaveIncrementsTheTallyOnce() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        try select(model, "eefa")
        model.write = "Aoife"

        await model.copy()
        await model.save()

        let tally = await harness.store.load().correctionTally
        #expect(tally.map(\.heard) == ["eefa"])
        #expect(tally.map(\.count) == [1])
    }

    // MARK: - Validation (R5)

    @Test func emptyHeardBlocksTheWrite() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()

        #expect(model.validationError == "Select the misheard phrase first.")
        await model.save()
        #expect(!model.saved)
        #expect(await harness.store.load().corrections.isEmpty)
    }

    @Test func emptyWriteBlocksTheWrite() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        try select(model, "eefa")
        model.write = "  "

        #expect(model.validationError == "Enter the spelling to write.")
        await model.save()
        #expect(await harness.store.load().corrections.isEmpty)
    }

    @Test func writeIdenticalToHeardBlocksTheWrite() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()

        try select(model, "eefa")

        #expect(model.validationError == "Nothing to remember — Write is the same as Heard.")
        await model.save()
        #expect(await harness.store.load().corrections.isEmpty)
    }

    @Test func aPhraseAlreadyRememberedInTheSameScopeBlocksTheWrite() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        var config = Config()
        config.corrections = [CorrectionRule(
            heard: "eefa", write: "Aoife", bundleID: "com.tinyspeck.slackmacgap"
        )]
        let model = harness.model(config: config)
        try select(model, "eefa")
        model.write = "Aoifé"

        #expect(model.validationError == "‘eefa’ is already remembered for Slack as ‘Aoife’.")
        await model.save()
        #expect(await harness.store.load().corrections.isEmpty)
    }

    @Test func aCaseOnlyFixIsAllowed() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        try select(model, "get hub")
        model.write = "Get Hub"

        #expect(model.validationError == nil)
        await model.save()

        #expect(await harness.store.load().corrections.map(\.write) == ["Get Hub"])
    }
}
