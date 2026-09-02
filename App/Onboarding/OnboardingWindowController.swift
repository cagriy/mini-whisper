import AVFoundation
import AppKit
import ApplicationServices
import MWSupport

extension PermissionMonitor {
    static func granted(_ permission: OnboardingPermission) -> Bool {
        switch permission {
        case .microphone: microphoneGranted
        case .accessibility: accessibilityGranted
        }
    }

    /// Triggers the system prompt for one permission. The microphone prompt only
    /// exists while the status is undetermined; Accessibility is asked for with the
    /// trust-check option (`onboarding.py:_request_permission`).
    static func request(_ permission: OnboardingPermission) {
        switch permission {
        case .microphone:
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .accessibility:
            // The literal name, as `onboarding.py` uses: the `kAXTrustedCheckOptionPrompt`
            // global is a `var` and so not readable under Swift 6 strict concurrency.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }
}

/// F33's parity wizard: the source's geometry, labels and 1.5 s poll, unclosable,
/// and a Continue that starts normal operation in this process rather than
/// relaunching the bundle as `onboarding.py:_on_continue` does.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private enum Layout {
        static let width: CGFloat = 460
        static let height: CGFloat = 275
        static let padding: CGFloat = 30
        static let cell: CGFloat = 30
        static let symbolPointSize: CGFloat = 15
        static let rowHeight: CGFloat = 38
    }

    private let onContinue: () -> Void
    private let window: NSWindow
    private var model: OnboardingModel
    private var timer: Timer?
    private var indicators: [OnboardingPermission: NSImageView] = [:]
    private var openButtons: [OnboardingPermission: NSButton] = [:]
    private let statusLabel: NSTextField
    private let continueButton: NSButton

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        model = OnboardingModel(
            isGranted: { PermissionMonitor.granted($0) },
            request: { PermissionMonitor.request($0) }
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        statusLabel = Self.label(
            frame: .zero,
            text: "Grant all permissions to continue.",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        continueButton = NSButton(frame: .zero)
        super.init()
        build()
    }

    func show() {
        model.start()
        refresh()

        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated { self.poll() }
        }
        self.timer = timer

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The window cannot be dismissed while a permission is missing (F33).
    func windowShouldClose(_ sender: NSWindow) -> Bool { false }

    // MARK: - Layout

    private func build() {
        window.title = "Mini Whisper — Setup"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        guard let content = window.contentView else { return }
        let pad = Layout.padding
        var y = Layout.height - 65

        content.addSubview(Self.label(
            frame: NSRect(x: pad, y: y, width: Layout.width - 2 * pad, height: 28),
            text: "Mini Whisper needs a few permissions",
            font: .boldSystemFont(ofSize: 18)
        ))

        y -= 22
        let subtitle = Self.label(
            frame: NSRect(x: pad, y: y - 30, width: Layout.width - 2 * pad, height: 46),
            text: "Grant the permissions Mini Whisper requires. Microphone access is needed to"
                + " transcribe speech, and Accessibility access allows pasting the transcribed"
                + " text into other apps.",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        subtitle.cell?.wraps = true
        content.addSubview(subtitle)

        y -= 46
        for permission in OnboardingModel.steps {
            y -= Layout.rowHeight
            addRow(for: permission, to: content, y: y)
        }

        y -= 44
        let buttonWidth: CGFloat = 110
        let buttonX = Layout.width - pad - buttonWidth - 20
        statusLabel.frame = NSRect(x: pad, y: y + 7, width: buttonX - pad - 8, height: 18)
        content.addSubview(statusLabel)

        continueButton.frame = NSRect(x: buttonX, y: y, width: buttonWidth, height: 32)
        continueButton.title = "Continue"
        continueButton.bezelStyle = .rounded
        continueButton.isEnabled = false
        continueButton.keyEquivalent = "\r"
        continueButton.target = self
        continueButton.action = #selector(continueClicked)
        content.addSubview(continueButton)
    }

    private func addRow(for permission: OnboardingPermission, to content: NSView, y: CGFloat) {
        let pad = Layout.padding
        let cell = Layout.cell
        let iconY = y + 8
        let textX = pad + 2 * cell + 18

        let indicator = NSImageView(frame: NSRect(x: pad, y: iconY, width: cell, height: cell))
        indicators[permission] = indicator
        content.addSubview(indicator)

        let icon = NSImageView(frame: NSRect(x: pad + cell + 8, y: iconY, width: cell, height: cell))
        icon.image = Self.symbol(permission.symbolName, description: permission.label)
        icon.contentTintColor = .secondaryLabelColor
        content.addSubview(icon)

        content.addSubview(Self.label(
            frame: NSRect(x: textX, y: y + 13, width: Layout.width - textX - 130, height: 18),
            text: permission.label,
            font: .systemFont(ofSize: 13, weight: .medium)
        ))

        let button = NSButton(frame: NSRect(x: Layout.width - pad - 130, y: y + 5, width: 110, height: 35))
        button.title = "Open Settings"
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 11)
        button.target = self
        button.action = #selector(openSettings(_:))
        button.tag = OnboardingModel.steps.firstIndex(of: permission) ?? 0
        openButtons[permission] = button
        content.addSubview(button)
    }

    private static func label(
        frame: NSRect,
        text: String,
        font: NSFont,
        color: NSColor? = nil
    ) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.font = font
        if let color { label.textColor = color }
        return label
    }

    private static func symbol(_ name: String, description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: Layout.symbolPointSize, weight: .medium)
            )
    }

    // MARK: - State

    private func poll() {
        model.poll()
        refresh()
    }

    private func refresh() {
        for permission in OnboardingModel.steps {
            let granted = model.granted(permission)
            indicators[permission]?.image = Self.symbol(
                granted ? "checkmark.circle.fill" : "xmark.circle.fill",
                description: granted ? "granted" : "not granted"
            )
            indicators[permission]?.contentTintColor = granted ? .systemGreen : .systemRed
            openButtons[permission]?.isHidden = granted
        }
        continueButton.isEnabled = model.continueEnabled
        statusLabel.stringValue = model.statusText
        statusLabel.textColor = model.allGranted ? .systemGreen : .secondaryLabelColor
    }

    @objc private func openSettings(_ sender: NSButton) {
        guard OnboardingModel.steps.indices.contains(sender.tag) else { return }
        NSWorkspace.shared.open(OnboardingModel.steps[sender.tag].settingsURL)
    }

    @objc private func continueClicked() {
        timer?.invalidate()
        timer = nil
        window.delegate = nil
        window.close()
        NSApp.setActivationPolicy(.accessory)
        Log.ui.info("Onboarding complete; starting in-process")
        onContinue()
    }
}
