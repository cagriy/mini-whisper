import Foundation
import MWConfig
import MWMeetingPipeline
import MWMeetings
import MWTestCall
import Observation

/// The test-call setup page (design §3 R1, R2, R5, §5.4 Chooser and setup): the scenario, engine
/// and Overlap a test call starts with, and whether this Mac's voices allow one at all.
@MainActor
@Observable
final class TestCallSetupModel {
    struct ScenarioOption: Equatable, Identifiable {
        let choice: ScenarioChoice
        let title: String

        var id: ScenarioChoice { choice }
    }

    struct EngineOption: Equatable, Identifiable {
        let engine: MeetingEngine
        let title: String
        /// False without the engine's key.
        let enabled: Bool

        var id: MeetingEngine { engine }
    }

    var choice: ScenarioChoice = .random
    /// Preselected as the engine Settings would use; nil without any key.
    var engine: MeetingEngine?
    var overlap = false

    private let keyedEngines: Set<MeetingEngine>
    private let defaultEngine: MeetingEngine?
    /// Nil until `say -v ?` has been read.
    private var voices: [SystemVoice]?
    /// Each scenario's casting onto `voices`, by scenario id.
    private var castings: [String: VoiceCasting] = [:]
    private var latestWER: [String: Double] = [:]

    init(keyedEngines: Set<MeetingEngine>, defaultEngine: MeetingEngine?) {
        self.keyedEngines = keyedEngines
        self.defaultEngine = defaultEngine
        engine = defaultEngine
    }

    // MARK: - Outputs

    var randomOption: ScenarioOption {
        ScenarioOption(choice: .random, title: "Random · one of \(ScenarioLibrary.all.count)")
    }

    /// "<Title> — WER 6.4%" or "<Title> — not run", and the voices this Mac substitutes.
    var scenarioOptions: [ScenarioOption] {
        ScenarioLibrary.all.map { scenario in
            var title = scenario.title + " — " + (latestWER[scenario.id].map { String(format: "WER %.1f%%", $0 * 100) } ?? "not run")
            if case .ready(let casting)? = castings[scenario.id] {
                let substitutes = [TestCallRole.a, .b].compactMap { casting[$0] }.filter { $0.voice != $0.requested }
                if !substitutes.isEmpty {
                    title += " · uses " + substitutes.map { "\($0.voice) for \($0.character)" }.joined(separator: ", ")
                }
            }
            return ScenarioOption(choice: .named(scenario.id), title: title)
        }
    }

    var engineOptions: [EngineOption] {
        MeetingEngine.allCases.map { engine in
            let enabled = keyedEngines.contains(engine)
            let note = !enabled ? " — no key" : engine == defaultEngine ? " — default" : ""
            return EngineOption(engine: engine, title: engine.title + note, enabled: enabled)
        }
    }

    /// The chooser's Test Call… link: the voices are read and two English ones exist (R5).
    var canOpen: Bool {
        !castings.isEmpty && !castings.values.contains(.unavailable)
    }

    var linkHelp: String? {
        castings.values.contains(.unavailable) ? TestCallSetup.voicesUnavailable : nil
    }

    var canStart: Bool { setup != nil }

    /// The chooser's no-key message (R2).
    var startBlockedReason: String? {
        keyedEngines.isEmpty ? MeetingError.noEngineKey.errorDescription : nil
    }

    /// What Start Test Call starts.
    var setup: TestCallSetup? {
        guard canOpen, let voices, let engine, keyedEngines.contains(engine) else { return nil }
        return TestCallSetup(choice: choice, engine: engine, overlap: overlap, voices: voices)
    }

    // MARK: - Inputs

    /// This Mac's voices, read once per chooser open.
    func showVoices(_ voices: [SystemVoice]) {
        self.voices = voices
        let catalog = VoiceCatalog(voices: voices)
        castings = Dictionary(uniqueKeysWithValues: ScenarioLibrary.all.map { ($0.id, catalog.cast($0)) })
    }

    /// Each scenario's latest WER at its current revision.
    func showLatestWER(_ wer: [String: Double]) {
        latestWER = wer
    }
}
