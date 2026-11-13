import AppKit

/// `LSUIElement` apps have no menu bar, so ⌘C/⌘V would not work in the key and
/// prompt fields. Port of `settings.py:_ensure_edit_menu`.
@MainActor
enum EditMenu {
    static func ensure() {
        let mainMenu = NSApp.mainMenu ?? {
            let menu = NSMenu()
            NSApp.mainMenu = menu
            return menu
        }()
        guard !mainMenu.items.contains(where: { $0.title == "Edit" }) else { return }

        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }

        let item = NSMenuItem()
        item.title = "Edit"
        item.submenu = editMenu
        mainMenu.addItem(item)
    }
}
