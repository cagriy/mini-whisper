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
    private let onStartMeeting: () -> Void
    private let onStopMeeting: () -> Void
    private let onShowMeeting: () -> Void
    private let onMeetings: () -> Void
    private let onDictations: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private var model = MenuModel()

    init(
        sounds: any SoundPlaying,
        onCorrectLast: @escaping () -> Void,
        onStartMeeting: @escaping () -> Void,
        onStopMeeting: @escaping () -> Void,
        onShowMeeting: @escaping () -> Void,
        onMeetings: @escaping () -> Void,
        onDictations: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.sounds = sounds
        self.onCorrectLast = onCorrectLast
        self.onStartMeeting = onStartMeeting
        self.onStopMeeting = onStopMeeting
        self.onShowMeeting = onShowMeeting
        self.onMeetings = onMeetings
        self.onDictations = onDictations
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

    func setUsage(_ totals: UsageTotals) {
        model.setUsage(totals)
        rebuild()
    }

    func setLast(_ dictation: DeliveredDictation) {
        model.setLast(dictation)
        rebuild()
    }

    var lastDictation: DeliveredDictation? { model.lastDictation }

    func setMeetingActive(_ active: Bool) {
        model.setMeetingActive(active)
        rebuild()
    }

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
        case .startMeeting: onStartMeeting()
        case .stopMeeting: onStopMeeting()
        case .showMeeting: onShowMeeting()
        case .meetings: onMeetings()
        case .dictations: onDictations()
        case .settings: onSettings()
        case .checkForUpdates: AppUpdater.checkForUpdates()
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
