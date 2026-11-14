import MWConfig
import MWTestCall
import SwiftUI

/// Design §5.9 *Chooser and Test Call setup*: the chooser's test-call step, reached by its Test
/// Call… link: the scenario, engine and Overlap, then Start Test Call.
struct TestCallSetupView: View {
    let model: MeetingWindowModel
    let actions: MeetingActions

    var body: some View {
        @Bindable var setup = model.setup
        VStack(spacing: 0) {
            TopBar {
                Button(action: model.closeTestCallSetup) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.pill(size: .small))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s5) {
                        Text("Test call").textStyle(.display).foregroundStyle(DS.Colors.text)
                        TestTag()
                    }
                    Text(
                        "Two simulated voices talk with you from a script, as on a remote call. You read your lines"
                            + " from the screen. At Stop the transcript is scored against the script. About 2 minutes,"
                            + " about $0.02."
                    )
                    .textStyle(.body)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -DS.Space.s5)
                    Card {
                        SettingRow("Scenario", description: "Latest score for each is shown in the list.") {
                            PillMenu(title: scenarioTitle) {
                                [PillMenu.Item(title: setup.randomOption.title) { setup.choice = .random }]
                                    + setup.scenarioOptions.enumerated().map { index, option in
                                        PillMenu.Item(title: option.title, separated: index == 0) {
                                            setup.choice = option.choice
                                        }
                                    }
                            }
                        }
                        SettingRow("Engine", description: "Only engines with a key can be chosen.") {
                            PillMenu(title: setup.engine?.title ?? "None") {
                                setup.engineOptions.map { option in
                                    PillMenu.Item(title: option.title, enabled: option.enabled) {
                                        setup.engine = option.engine
                                    }
                                }
                            }
                        }
                        SettingRow("Overlap", description: "A voice sometimes starts while you are still speaking.") {
                            Toggle("Overlap", isOn: $setup.overlap).toggleStyle(.ds)
                        }
                    }
                    if let error = model.errorMessage {
                        ErrorLine(error)
                    }
                    HStack(spacing: DS.Space.s4) {
                        if let reason = setup.startBlockedReason {
                            Text(reason).textStyle(.body).foregroundStyle(DS.Colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Button("Cancel", action: actions.cancel)
                            .buttonStyle(.pill())
                            .keyboardShortcut(.cancelAction)
                        Button("Start Test Call") {
                            if let start = setup.setup { actions.startTestCall(start) }
                        }
                        .buttonStyle(.pill(.primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!setup.canStart)
                    }
                }
                .padding(EdgeInsets(top: DS.Space.s6, leading: 32, bottom: 56, trailing: 32))
                .frame(maxWidth: DS.Size.pageColumn, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The scenario's own title; the menu's entries add its latest score and voices.
    private var scenarioTitle: String {
        guard case .named(let id) = model.setup.choice,
              let scenario = ScenarioLibrary.all.first(where: { $0.id == id })
        else { return model.setup.randomOption.title }
        return scenario.title
    }
}
