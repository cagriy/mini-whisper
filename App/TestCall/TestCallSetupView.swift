import MWConfig
import MWTestCall
import SwiftUI

/// Design §5.4 Chooser and setup (mockup `mockup-v5-chooser-options.html#test-link`): the chooser
/// window's test-call page, reached by its Test Call… link.
struct TestCallSetupView: View {
    let model: MeetingWindowModel
    let actions: MeetingActions

    var body: some View {
        @Bindable var setup = model.setup
        VStack(alignment: .leading, spacing: 16) {
            Button("‹ Back", action: model.closeTestCallSetup).buttonStyle(.link)
            HStack(spacing: 8) {
                Text("Test call").font(.title2.weight(.semibold))
                TestTag()
            }
            Text(
                "Two simulated voices talk with you from a script, as on a remote call. You read your lines from"
                    + " the screen. At Stop the transcript is scored against the script. About 2 minutes, about $0.02."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                GridRow {
                    label("Scenario")
                    Picker("Scenario", selection: $setup.choice) {
                        Text(setup.randomOption.title).tag(setup.randomOption.choice)
                        Divider()
                        ForEach(setup.scenarioOptions) { Text($0.title).tag($0.choice) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    label("Engine")
                    Picker("Engine", selection: $setup.engine) {
                        ForEach(setup.engineOptions) { option in
                            Text(option.title).tag(Optional(option.engine)).disabled(!option.enabled)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Toggle(isOn: $setup.overlap) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Overlap")
                            Text("A voice sometimes starts while you are still speaking.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
            Spacer()
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            HStack {
                if let reason = setup.startBlockedReason {
                    Text(reason).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: actions.cancel).keyboardShortcut(.cancelAction)
                Button("Start Test Call") {
                    if let start = setup.setup { actions.startTestCall(start) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!setup.canStart)
            }
        }
        .padding(28)
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }
}
