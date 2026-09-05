import AppKit
import MWPipeline
import MWUsage

/// The menu-bar item and its menu (F31). All contents come from `MenuModel`;
/// this type only mirrors them into `NSMenu` and routes clicks.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let sounds: any SoundPlaying
    private let onCorrectLast: () -> Void
    private let onHistory: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private var model = MenuModel()

    init(
        sounds: any SoundPlaying,
        onCorrectLast: @escaping () -> Void,
        onHistory: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.sounds = sounds
        self.onCorrectLast = onCorrectLast
        self.onHistory = onHistory
        self.onSettings = onSettings
        self.onQuit = onQuit
        super.init()

        if let button = statusItem.button {
            let image = Bundle.main.image(forResource: "mini-whisper")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
        }
        statusItem.menu = NSMenu()
        rebuild()
    }

    func setUsage(today: String, month: String) {
        model.setUsage(today: today, month: month)
        rebuild()
    }

    func setUsage(today: DayEntry, monthCost: Double) {
        model.setUsage(today: today, monthCost: monthCost)
        rebuild()
    }

    func setLast(_ dictation: DeliveredDictation) {
        model.setLast(dictation)
        rebuild()
    }

    var lastDictation: DeliveredDictation? { model.lastDictation }

    private func rebuild() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()
        for item in model.items {
            guard !item.isSeparator else {
                menu.addItem(.separator())
                continue
            }
            let menuItem = NSMenuItem(
                title: item.title,
                action: item.action == nil ? nil : #selector(handle(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item.action.map(ActionBox.init)
            menu.addItem(menuItem)
        }
    }

    @objc private func handle(_ sender: NSMenuItem) {
        guard let action = (sender.representedObject as? ActionBox)?.action else { return }
        switch action {
        case .copyLast: copyLast()
        case .correctLast: onCorrectLast()
        case .history: onHistory()
        case .settings: onSettings()
        case .about: AboutPanel.show()
        case .quit: onQuit()
        }
    }

    private func copyLast() {
        guard !model.lastText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.lastText, forType: .string)
        sounds.playOn()
    }

    private final class ActionBox: NSObject {
        let action: MenuItem.Action
        init(_ action: MenuItem.Action) { self.action = action }
    }
}
