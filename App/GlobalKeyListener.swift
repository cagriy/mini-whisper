import ApplicationServices
import CoreGraphics
import Foundation
import MWHotkeys
import MWSupport
import os

/// The `CGEventTap` and its `HotkeyMatcher`, on a dedicated thread with its own run
/// loop (design §5.2). Events are converted by `CGEventConversion`, matched under a
/// lock, and the resulting actions delivered on the main actor. A 100 ms watchdog runs
/// only while a binding is active (F6) and the tap is re-enabled whenever the system
/// disables it (§5.7).
final class GlobalKeyListener: HotkeyCapturing, @unchecked Sendable {
    private static let watchdogInterval = DispatchTimeInterval.milliseconds(100)
    private static let accessibilityLostMessage = "Accessibility permission lost — re-enable in System Settings"

    private let onAction: @MainActor @Sendable (HotkeyAction) -> Void
    private let onError: @MainActor @Sendable (String) -> Void
    private let matcher: OSAllocatedUnfairLock<HotkeyMatcher>
    private let queue = DispatchQueue(label: "com.ips.mini-whisper.hotkey-watchdog")
    private let clock = SystemClock()
    private let errorShown = OSAllocatedUnfairLock(initialState: false)

    /// `thread`, `runLoop`, `tap` and `watchdog` are touched from the caller, the tap
    /// thread and the watchdog queue, so they live behind this lock.
    private let stateLock = NSLock()
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private var watchdog: DispatchSourceTimer?

    init(
        bindings: [BindingName: HotkeyCombo],
        onAction: @escaping @MainActor @Sendable (HotkeyAction) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        matcher = OSAllocatedUnfairLock(initialState: HotkeyMatcher(bindings: bindings))
        self.onAction = onAction
        self.onError = onError
    }

    func start() {
        let thread = Thread { [weak self] in self?.runTapLoop() }
        thread.name = "com.ips.mini-whisper.hotkey"
        thread.qualityOfService = .userInteractive
        let alreadyStarted = stateLock.withLock {
            guard self.thread == nil else { return true }
            self.thread = thread
            return false
        }
        guard !alreadyStarted else { return }
        thread.start()
    }

    func stop() {
        stopWatchdog()
        let (tap, runLoop) = stateLock.withLock {
            defer { (self.thread, self.runLoop, self.tap) = (nil, nil, nil) }
            return (self.tap, self.runLoop)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    /// F7: the Settings hotkey fields put the live matcher into capture mode, so
    /// there is exactly one matcher in the process.
    func beginCapture() {
        matcher.withLock { $0.beginCapture() }
    }

    func cancelCapture() {
        matcher.withLock { $0.cancelCapture() }
    }

    func update(binding: BindingName, combo: HotkeyCombo) {
        matcher.withLock { $0.update(binding: binding, combo: combo) }
        Log.hotkey.info("Binding \(binding.rawValue) is now \(combo.configString)")
        syncWatchdog()
    }

    // MARK: - Tap thread

    private func runTapLoop() {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, context in
                guard let context else { return nil }
                Unmanaged<GlobalKeyListener>.fromOpaque(context)
                    .takeUnretainedValue()
                    .receive(type: type, event: event)
                return nil
            },
            // Unretained: `AppDelegate` owns the listener for the process's lifetime.
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.hotkey.error("Could not create the event tap; Accessibility is not granted")
            reportAccessibilityLost()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        stateLock.withLock {
            self.tap = tap
            self.runLoop = CFRunLoopGetCurrent()
        }
        Log.hotkey.info("Event tap installed")
        CFRunLoopRun()
    }

    private func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenableTap(reason: type == .tapDisabledByTimeout ? "timeout" : "user input")
            return
        }
        guard let keyEvent = CGEventConversion.keyEvent(
            type: type,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags.rawValue,
            characters: type == .keyDown ? Self.characters(of: event) : nil
        ) else { return }

        let now = clock.now
        deliver(matcher.withLock { $0.handle(keyEvent, now: now) })
        syncWatchdog()
    }

    private static func characters(of event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: length)
    }

    private func reenableTap(reason: String) {
        guard let tap = stateLock.withLock({ self.tap }) else { return }
        guard AXIsProcessTrusted() else {
            Log.hotkey.error("Event tap disabled by \(reason) and Accessibility is gone")
            reportAccessibilityLost()
            return
        }
        Log.hotkey.warning("Event tap disabled by \(reason); re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func reportAccessibilityLost() {
        let alreadyShown = errorShown.withLock { shown -> Bool in
            let was = shown
            shown = true
            return was
        }
        guard !alreadyShown else { return }
        let handler = onError
        DispatchQueue.main.async {
            MainActor.assumeIsolated { handler(Self.accessibilityLostMessage) }
        }
    }

    private func deliver(_ actions: [HotkeyAction]) {
        guard !actions.isEmpty else { return }
        let handler = onAction
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for action in actions { handler(action) }
            }
        }
    }

    // MARK: - Watchdog

    /// Runs only while a binding is active, so an idle app schedules nothing (N1).
    private func syncWatchdog() {
        if matcher.withLock({ $0.needsWatchdog }) {
            startWatchdog()
        } else {
            stopWatchdog()
        }
    }

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let alreadyRunning = stateLock.withLock {
            guard watchdog == nil else { return true }
            watchdog = timer
            return false
        }
        guard !alreadyRunning else { return }
        timer.schedule(deadline: .now() + Self.watchdogInterval, repeating: Self.watchdogInterval)
        timer.setEventHandler { [weak self] in self?.watchdogTick() }
        timer.resume()
    }

    private func stopWatchdog() {
        let timer = stateLock.withLock {
            defer { watchdog = nil }
            return watchdog
        }
        timer?.cancel()
    }

    private func watchdogTick() {
        if let tap = stateLock.withLock({ self.tap }), !CGEvent.tapIsEnabled(tap: tap) {
            reenableTap(reason: "watchdog")
        }
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        deliver(matcher.withLock { $0.watchdogTick(osFlags: CGEventConversion.modifierFlags(flags)) })
        syncWatchdog()
    }
}
