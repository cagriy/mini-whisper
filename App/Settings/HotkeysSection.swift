import MWHotkeys
import SwiftUI

/// F8's two bindings and the meeting toggle, captured with the source's field behaviour.
struct HotkeysSection: View {
    let model: SettingsModel

    var body: some View {
        SettingsPane(title: "Hotkeys") {
            ForEach(BindingName.allCases, id: \.self) { binding in
                VStack(alignment: .trailing, spacing: 4) {
                    HotkeyCaptureField(title: SettingsModel.title(of: binding), binding: binding, model: model)
                    if let error = model.hotkeyError(for: binding) {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            SettingsFootnote(
                "Click a field, then press the shortcut. Hold to record, release to paste;"
                    + " tap to toggle. Modifier-only shortcuts such as Right ⌘ are allowed."
            )
        }
    }
}
