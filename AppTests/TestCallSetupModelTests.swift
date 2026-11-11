import Foundation
import MWConfig
import MWMeetings
import MWStreaming
import MWTestCall
import Testing
@testable import MiniWhisper

@MainActor
@Suite struct TestCallSetupModelTests {
    /// This Mac's English voices without Karen, plus one Italian voice.
    private static let voices = [
        SystemVoice(name: "Daniel", locale: "en_GB"),
        SystemVoice(name: "Fred", locale: "en_US"),
        SystemVoice(name: "Moira", locale: "en_IE"),
        SystemVoice(name: "Rishi", locale: "en_IN"),
        SystemVoice(name: "Samantha", locale: "en_US"),
        SystemVoice(name: "Tessa", locale: "en_ZA"),
        SystemVoice(name: "Alice", locale: "it_IT"),
    ]

    private func setup(
        keys: Set<MeetingEngine> = [.assemblyaiStreaming, .assemblyaiPro],
        default engine: MeetingEngine? = .assemblyaiStreaming,
        voices: [SystemVoice]? = voices
    ) -> TestCallSetupModel {
        let setup = TestCallSetupModel(keyedEngines: keys, defaultEngine: engine)
        if let voices { setup.showVoices(voices) }
        return setup
    }

    @Test func scenarioMenuRows() {
        let setup = setup()
        setup.showLatestWER(["sprint-planning": 0.064, "budget-review": 0.0912])

        #expect(setup.randomOption.title == "Random · one of 8")
        #expect(setup.randomOption.choice == .random)
        let rows = setup.scenarioOptions
        #expect(rows.map(\.choice) == ScenarioLibrary.all.map { .named($0.id) })
        #expect(rows.map(\.title) == [
            "Sprint planning — WER 6.4% · uses Fred for Priya",
            "Budget review — WER 9.1%",
            "Incident review — not run",
            "Hiring debrief — not run · uses Daniel for Claire",
            "Product launch — not run",
            "Customer escalation — not run",
            "Office move — not run · uses Daniel for Megan",
            "Quarterly sales — not run",
        ])
    }

    @Test func engineMenuListsAllFourWithDefaultAndNoKey() {
        let options = setup().engineOptions

        #expect(options.map(\.engine) == MeetingEngine.allCases)
        #expect(options.map(\.title) == [
            "Speechmatics Standard — no key",
            "Speechmatics Enhanced — no key",
            "AssemblyAI Universal-Streaming — default",
            "AssemblyAI Universal 3.6 Pro",
        ])
        #expect(options.map(\.enabled) == [false, false, true, true])
    }

    @Test func defaultEngineIsPreselected() {
        let setup = setup(keys: Set(MeetingEngine.allCases), default: .speechmaticsEnhanced)

        #expect(setup.engine == .speechmaticsEnhanced)
        #expect(setup.choice == .random)
        #expect(setup.overlap == false)
        #expect(setup.engineOptions.filter(\.enabled).count == 4)
    }

    @Test func startIsDisabledWithoutAnyKeyAndShowsTheNoKeyMessage() {
        let none = setup(keys: [], default: nil)

        #expect(none.engine == nil)
        #expect(none.canStart == false)
        #expect(none.setup == nil)
        #expect(none.startBlockedReason == "Add a Speechmatics or AssemblyAI key under Keys.")
        #expect(none.engineOptions.map(\.enabled) == [false, false, false, false])

        let keyed = setup()
        #expect(keyed.canStart)
        #expect(keyed.startBlockedReason == nil)
    }

    @Test func linkIsDisabledWithFewerThanTwoEnglishVoices() {
        let loading = setup(voices: nil)
        #expect(loading.canOpen == false)
        #expect(loading.linkHelp == nil)
        #expect(loading.canStart == false)

        let one = setup(voices: [SystemVoice(name: "Daniel", locale: "en_GB"), SystemVoice(name: "Alice", locale: "it_IT")])
        #expect(one.canOpen == false)
        #expect(one.linkHelp
            == "Test calls need two English voices. Add one in System Settings → Accessibility → Spoken Content.")
        #expect(one.canStart == false)

        let two = setup(voices: [SystemVoice(name: "Daniel", locale: "en_GB"), SystemVoice(name: "Moira", locale: "en_IE")])
        #expect(two.canOpen)
        #expect(two.linkHelp == nil)
    }

    @Test func backReturnsToTheChooser() {
        let model = MeetingWindowModel(chooser: MeetingWindowModel.Chooser(
            config: Config(), platform: PlatformInfo(osMajor: 26, osMinor: 0), accountName: "Alex",
            hasKey: { $0 == .assemblyai }
        ))
        #expect(model.chooser.keyedEngines == [.assemblyaiStreaming, .assemblyaiPro])
        #expect(model.setup.engine == .assemblyaiStreaming)

        model.openTestCallSetup()
        #expect(model.showsTestCallSetup == false)

        model.setup.showVoices(Self.voices)
        model.openTestCallSetup()
        #expect(model.showsTestCallSetup)

        model.closeTestCallSetup()
        #expect(model.showsTestCallSetup == false)
    }

    @Test func startTestCallCarriesChoiceEngineOverlapAndVoices() {
        let setup = setup()
        setup.choice = .named("budget-review")
        setup.engine = .assemblyaiPro
        setup.overlap = true

        #expect(setup.setup == TestCallSetup(
            choice: .named("budget-review"), engine: .assemblyaiPro, overlap: true, voices: Self.voices
        ))

        setup.engine = .speechmaticsStandard
        #expect(setup.canStart == false)
        #expect(setup.setup == nil)
    }
}
