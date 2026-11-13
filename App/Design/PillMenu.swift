import AppKit
import SwiftUI

/// A pill that opens a menu, as `Export ▾` does. A SwiftUI `Menu` on macOS ignores a custom
/// button style, so the menu is AppKit's, opened under the pointer.
struct PillMenu: View {
    struct Item {
        let title: String
        var enabled = true
        /// A separator goes above it.
        var separated = false
        let action: @MainActor () -> Void
    }

    let title: String
    var size = PillButtonStyle.Size.small
    /// Read when the menu opens.
    let items: () -> [Item]

    var body: some View {
        Button { Self.popUp(items()) } label: {
            HStack(spacing: DS.Space.s2) {
                Text(title)
                Image(systemName: "chevron.down").font(DS.TextStyle.label.font)
            }
        }
        .buttonStyle(.pill(size: size))
    }

    private static func popUp(_ items: [Item]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            if item.separated { menu.addItem(.separator()) }
            let handler = Handler(item.action)
            let entry = NSMenuItem(title: item.title, action: #selector(Handler.run), keyEquivalent: "")
            entry.target = handler
            // A menu item holds its target weakly.
            entry.representedObject = handler
            entry.isEnabled = item.enabled
            menu.addItem(entry)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

@MainActor
private final class Handler: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func run() { action() }
}
