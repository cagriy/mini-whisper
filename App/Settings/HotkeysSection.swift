import MWHotkeys
import SwiftUI

/// The two bindings of F8, captured with the source's field behaviour.
struct HotkeysSection: View {
    let model: SettingsModel

    var body: some View {
        SettingsPane(title: "Hotkeys") {
            HotkeyCaptureField(title: "Record", binding: .paste, model: model)
            HotkeyCaptureField(title: "Record and submit", binding: .pasteSubmit, model: model)
            SettingsFootnote(
                "Click a field, then press the shortcut. Hold to record, release to paste;"
                    + " tap to toggle. Modifier-only shortcuts such as Right ⌘ are allowed."
            )
        }
    }
}
