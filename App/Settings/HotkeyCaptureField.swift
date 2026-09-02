import MWHotkeys
import SwiftUI

/// A click-to-capture hotkey field (F7). The keys themselves arrive through the
/// live `HotkeyMatcher` in capture mode, not the responder chain, so this is a
/// button that shows the current combo — or `Press shortcut...` while capturing.
/// Esc is routed here by the window's `cancelOperation(_:)`.
struct HotkeyCaptureField: View {
    let title: String
    let binding: BindingName
    let model: SettingsModel

    private var isCapturing: Bool { model.capturing == binding }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                model.beginCapture(binding)
            } label: {
                Text(model.display(binding))
                    .foregroundStyle(isCapturing ? .secondary : .primary)
                    .frame(width: 200)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isCapturing ? Color.accentColor : Color(nsColor: .separatorColor))
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
