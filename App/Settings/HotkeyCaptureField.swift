import MWHotkeys
import SwiftUI

/// A click-to-capture hotkey field (F7). The keys themselves arrive through the
/// live `HotkeyMatcher` in capture mode, not the responder chain, so this is a
/// button that shows the current combo — or `Press shortcut...` while capturing.
/// Esc is routed here by the window's `cancelOperation(_:)`.
struct HotkeyCaptureField: View {
    let binding: BindingName
    let model: SettingsModel

    private var isCapturing: Bool { model.capturing == binding }

    var body: some View {
        Button {
            model.beginCapture(binding)
        } label: {
            Text(model.display(binding))
                .textStyle(.body)
                .foregroundStyle(isCapturing ? DS.Colors.textSecondary : DS.Colors.text)
                .frame(width: 200, height: DS.Size.control)
                .modifier(FieldChrome(
                    shape: RoundedRectangle(cornerRadius: DS.Radius.field), fill: DS.Colors.canvas, focused: isCapturing
                ))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SettingsModel.title(of: binding))
        .accessibilityValue(model.display(binding))
    }
}
