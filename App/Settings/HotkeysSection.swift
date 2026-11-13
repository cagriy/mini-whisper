import MWHotkeys
import SwiftUI

/// F8's two bindings and the meeting toggle, captured with the source's field behaviour.
struct HotkeysSection: View {
    let model: SettingsModel

    var body: some View {
        Card {
            ForEach(BindingName.allCases, id: \.self) { binding in
                SettingRow(
                    SettingsModel.title(of: binding),
                    description: binding == BindingName.allCases.last
                        ? "Click a field, then press the shortcut. Hold to record, release to paste;"
                            + " tap to toggle. Modifier-only shortcuts such as Right ⌘ are allowed."
                        : nil,
                    error: model.hotkeyError(for: binding)
                ) {
                    HotkeyCaptureField(binding: binding, model: model)
                }
            }
        }
    }
}
