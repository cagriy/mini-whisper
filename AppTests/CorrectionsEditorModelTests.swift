import Foundation
import MWConfig
import MWCorrections
import Testing
@testable import MiniWhisper

private let slackBundleID = "com.tinyspeck.slackmacgap"

private func rule(
    id: String,
    heard: String,
    write: String,
    soundsLike: [String] = [],
    bundleID: String? = nil,
    enabled: Bool = true
) -> CorrectionRule {
    CorrectionRule(
        id: id, heard: heard, write: write, soundsLike: soundsLike,
        bundleID: bundleID, enabled: enabled
    )
}

private let storedRules: [CorrectionRule] = [
    rule(id: "r1", heard: "eefa", write: "Aoife", soundsLike: ["eva"], bundleID: slackBundleID),
    rule(id: "r2", heard: "get hub", write: "GitHub"),
    rule(id: "r3", heard: "x code gen", write: "xcodegen", bundleID: "com.apple.Terminal",
         enabled: false),
]

@MainActor
@Suite struct CorrectionsEditorModelTests {
    private final class OpenedWindows: @unchecked Sendable {
        var sources: [CorrectionSource] = []
    }

    private struct Harness {
        let directory: URL
        let store: ConfigStore
        let opened = OpenedWindows()
        var apps = StubApps(names: [slackBundleID: "Slack"])

        init() {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("mw-corrections-\(UUID().uuidString)", isDirectory: true)
            store = ConfigStore(directory: directory)
        }

        func seed(_ mutate: @escaping @Sendable (inout Config) -> Void) async throws {
            try await store.update(mutate)
        }

        @MainActor
        func model() async -> CorrectionsEditorModel {
            CorrectionsEditorModel(
                config: await store.load(),
                store: store,
                apps: apps,
                openCorrection: { [opened] source in opened.sources.append(source) }
            )
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - Table (R33)

    @Test func rowsRenderStoredRulesInStoredOrder() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.seed { $0.corrections = storedRules }
        let model = await harness.model()

        #expect(model.rows.map(\.id) == ["r1", "r2", "r3"])
        #expect(model.rows.map(\.heard) == ["eefa", "get hub", "x code gen"])
        #expect(model.rows.map(\.write) == ["Aoife", "GitHub", "xcodegen"])
        // An app with no running instance still reads as a name, not a bundle ID.
        #expect(model.rows.map(\.scope) == ["Slack", "All apps", "Terminal"])
        #expect(model.rows.map(\.enabled) == [true, true, false])
    }

    // MARK: - Detail form (R34)

    @Test func detailFormEditsPersist() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.seed { $0.corrections = storedRules }
        let model = await harness.model()

        await model.setWrite("Aoífe", for: "r1")
        await model.setSoundsLike("eefa, eva , ", for: "r1")
        await model.setScope(nil, for: "r1")
        await model.setHeard("get hubb", for: "r2")

        let stored = try #require(await harness.store.load().corrections.first)
        #expect(stored.write == "Aoífe")
        #expect(stored.soundsLike == ["eefa", "eva"])
        #expect(stored.bundleID == nil)
        #expect(model.rows.first?.scope == "All apps")
        #expect(model.soundsLikeText(for: "r1") == "eefa, eva")
        #expect(await harness.store.load().corrections[1].heard == "get hubb")
        #expect(model.error == nil)
    }

    @Test func invalidEditShowsTheMessageAndWritesNothing() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.seed { $0.corrections = storedRules }
        let model = await harness.model()

        await model.setWrite("   ", for: "r1")
        #expect(model.error == "Enter the spelling to write.")
        #expect(model.rows.first?.write == "Aoife")
        #expect(await harness.store.load().corrections.first?.write == "Aoife")

        await model.setHeard("", for: "r1")
        #expect(model.error == "Select the misheard phrase first.")

        await model.setWrite("eefa", for: "r1")
        #expect(model.error == "Nothing to remember — Write is the same as Heard.")

        // R5's scope-aware duplicate, named by the app rather than its bundle ID.
        await model.setScope(slackBundleID, for: "r2")
        await model.setHeard("Eefa", for: "r2")
        #expect(model.error == "‘Eefa’ is already remembered for Slack as ‘Aoife’.")
        #expect(await harness.store.load().corrections[1].heard == "get hub")

        // A case-only fix is a change worth remembering.
        await model.setScope(nil, for: "r2")
        await model.setWrite("Get Hub", for: "r2")
        #expect(model.error == nil)
        #expect(await harness.store.load().corrections[1].write == "Get Hub")
    }

    @Test func enabledSwitchAndRemovePersist() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.seed { $0.corrections = storedRules }
        let model = await harness.model()
        model.selection = "r2"

        await model.setEnabled(false, for: "r2")
        #expect(model.rows[1].enabled == false)
        #expect(await harness.store.load().corrections[1].enabled == false)

        await model.remove("r2")
        #expect(model.rows.map(\.id) == ["r1", "r3"])
        #expect(model.selection == nil)
        #expect(await harness.store.load().corrections.map(\.id) == ["r1", "r3"])
    }

    // MARK: - Often corrected (R33, R35)

    @Test func tallyRowsAreTheTopFiveWithHasRule() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let now = Date(timeIntervalSince1970: 1_757_088_420)
        try await harness.seed {
            $0.corrections = storedRules
            $0.correctionTally = [
                CorrectionTallyEntry(heard: "eefa", count: 4, last: now),
                CorrectionTallyEntry(heard: "speech matics", count: 3, last: now),
                CorrectionTallyEntry(heard: "pie obj c", count: 2, last: now),
                CorrectionTallyEntry(heard: "you vee", count: 2, last: now.addingTimeInterval(-60)),
                // A disabled rule is no rule at all (R11).
                CorrectionTallyEntry(heard: "x code gen", count: 1, last: now),
                CorrectionTallyEntry(heard: "tahoe", count: 1, last: now.addingTimeInterval(-60)),
            ]
        }
        let model = await harness.model()

        #expect(model.tallyRows.map(\.heard)
            == ["eefa", "speech matics", "pie obj c", "you vee", "x code gen"])
        #expect(model.tallyRows.map(\.count) == [4, 3, 2, 2, 1])
        #expect(model.tallyRows.map(\.hasRule) == [true, false, false, false, false])
    }

    @Test func rememberOpensTheCorrectionWindowWithThePhrase() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()

        model.remember("speech matics")

        let source = try #require(harness.opened.sources.first)
        #expect(harness.opened.sources.count == 1)
        #expect(source.text == "speech matics")
        #expect(source.preselectAll)
        #expect(source.bundleID == nil)
    }

    // MARK: - Recognition hints (R33)

    @Test func hintRowsComeFromTheReportAndTheSupportConstant() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.seed {
            $0.corrections = storedRules
            $0.vocabulary = ["Tahoe"]
        }
        let model = await harness.model()

        #expect(model.hintRows.map(\.label) == [
            "SpeechAnalyzer", "On-device", "OpenAI Realtime", "ElevenLabs", "Speechmatics",
            "Batch transcription",
        ])
        // Aoife, eefa, eva, GitHub, get hub, Tahoe — the disabled rule contributes nothing.
        let onDevice = try #require(model.hintRows.first { $0.label == "On-device" })
        #expect(onDevice.detail == "6 hints sent · cap 100")
        #expect(onDevice.status == .ok)
        #expect(model.hintRows.first { $0.label == "OpenAI Realtime" }?.detail == "6 keywords sent")
        #expect(model.hintRows.first { $0.label == "ElevenLabs" }?.detail
            == "not sent in this version · rules still apply")
        #expect(model.hintRows.first { $0.label == "ElevenLabs" }?.status == .off)
        #expect(model.hintRows.last?.detail == "terms and corrections added to the prompt")

        let analyzer = try #require(model.hintRows.first)
        switch HintSupport.speechAnalyzer {
        case .supported:
            #expect(analyzer.detail == "6 hints sent · cap 100")
            #expect(analyzer.status == .ok)
        case .unavailable(let reason):
            #expect(analyzer.detail == "hints not sent · \(reason)")
            #expect(analyzer.status == .off)
        }
    }

    @Test func skippedHintsAreListedWithTheirReason() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        try await harness.seed {
            $0.vocabulary = ["mini whisper release notes bundle for the week"]
        }
        let model = await harness.model()

        let speechmatics = try #require(model.hintRows.first { $0.label == "Speechmatics" })
        #expect(speechmatics.detail
            == "0 entries sent · cap 1000 · 1 skipped:"
                + " “mini whisper release notes bundle for the week” is over 6 words")
        #expect(speechmatics.status == .warning)
    }

    // MARK: - Refresh (R36)

    @Test func refreshReplacesRowsFromAConfigTheModelDidNotWrite() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = await harness.model()
        #expect(model.rows.isEmpty)

        // The correction window's save, arriving through AppDelegate's config-change consumer.
        try await harness.seed {
            $0.corrections = storedRules
            $0.vocabulary = ["Tahoe"]
            $0.correctionTally = [
                CorrectionTallyEntry(heard: "eefa", count: 1, last: Date(timeIntervalSince1970: 1))
            ]
        }
        model.refresh(await harness.store.load())

        #expect(model.rows.map(\.id) == ["r1", "r2", "r3"])
        #expect(model.tallyRows.map(\.heard) == ["eefa"])
        #expect(model.hintRows.first { $0.label == "On-device" }?.detail == "6 hints sent · cap 100")
    }
}
