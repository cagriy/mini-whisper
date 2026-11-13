import SwiftUI

/// The switch, accent when on. It draws no label: the row it sits in names it, and the toggle's
/// own label reaches assistive technology only.
struct DSToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Switch(configuration: configuration)
    }

    /// A view of its own, as a style cannot read whether it is enabled.
    private struct Switch: View {
        let configuration: Configuration

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? DS.Colors.accent : DS.Colors.line)
                    .frame(width: 36, height: 20)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(DS.Colors.white)
                            .frame(width: 16, height: 16)
                            .shadow(color: DS.Colors.knobShadow, radius: 1, y: 1)
                            .padding(2)
                    }
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
                    .contentShape([.interaction, .focusEffect], Capsule())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.45)
            // The system switch is named explicitly: left to the environment it would be this style again.
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
            }
        }
    }
}

extension ToggleStyle where Self == DSToggleStyle {
    static var ds: DSToggleStyle { DSToggleStyle() }
}
