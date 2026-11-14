import AppKit
import MWConfig
import MWSupport

/// R8: the theme for every window, alert, popover and panel of the app at once. The dictation
/// overlay draws fixed colours, so it looks the same under each.
@MainActor
enum ThemeApplier {
    static func apply(_ theme: AppTheme) {
        NSApp.appearance = switch theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        Log.ui.info("Theme applied: \(theme.rawValue)")
    }
}
