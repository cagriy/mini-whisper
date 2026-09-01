import Foundation

/// Pure state machine over `KeyEvent`s for the two named bindings (F6, F7, F8).
///
/// Port of `hotkey.py:238-378` with two deliberate corrections:
/// - the watchdog releases modifier-trigger bindings too (`hotkey.py:286`
///   skipped them, so a missed key-up left them active forever);
/// - the held-modifier set is reconciled from each `flagsChanged`'s flags
///   rather than accumulated incrementally, so a missed event self-heals.
///
/// No timers, threads or platform imports live here — the 100 ms watchdog timer
/// belongs to the App's `GlobalKeyListener`.
public struct HotkeyMatcher: Sendable {
    private struct Binding {
        var combo: HotkeyCombo
        var isActive = false

        /// Everything that must be held for the binding to stay active: its
        /// modifiers plus, for a modifier trigger, the trigger's canonical form.
        var required: Set<Modifier> {
            combo.modifiers.union(combo.canonicalTrigger.map { [$0] } ?? [])
        }
    }

    private var bindings: [BindingName: Binding]
    private var pressedModifiers: Set<Modifier> = []
    private var captureModifiers: Set<Modifier> = []

    public private(set) var isCapturing = false

    public init(bindings: [BindingName: HotkeyCombo]) {
        self.bindings = bindings.mapValues { Binding(combo: $0) }
    }

    /// True while any active binding could still be released by the watchdog.
    public var needsWatchdog: Bool {
        bindings.values.contains { $0.isActive && !$0.required.isEmpty }
    }

    public mutating func handle(_ event: KeyEvent, now: TimeInterval) -> [HotkeyAction] {
        switch event {
        case .keyDown(let vk, let chars):
            return press(ResolvedKey(vk: vk, chars: chars))
        case .keyUp(let vk):
            return release(ResolvedKey(vk: vk, chars: nil))
        case .flagsChanged(let flags, let vk):
            pressedModifiers = flags.modifiers
            let key = ResolvedKey(vk: vk, chars: nil)
            guard case .modifier(let modifier, _) = key else {
                return isCapturing ? [] : safetyNet()
            }
            return flags.contains(modifier.flag) ? press(key) : release(key)
        }
    }

    public mutating func watchdogTick(osFlags: ModifierFlags) -> [HotkeyAction] {
        let held = osFlags.modifiers
        return deactivate { binding in
            !binding.required.isEmpty && !held.isSuperset(of: binding.required)
        }
    }

    public mutating func beginCapture() {
        isCapturing = true
        captureModifiers = []
    }

    public mutating func cancelCapture() {
        isCapturing = false
        captureModifiers = []
    }

    public mutating func update(binding name: BindingName, combo: HotkeyCombo) {
        bindings[name] = Binding(combo: combo)
        pressedModifiers = []
    }

    // MARK: - Matching

    private mutating func press(_ key: ResolvedKey) -> [HotkeyAction] {
        if isCapturing { return capturePress(key) }
        if case .modifier(let modifier, _) = key { pressedModifiers.insert(modifier) }

        var actions: [HotkeyAction] = []
        for name in BindingName.allCases {
            guard var binding = bindings[name], !binding.isActive, matches(key, binding) else { continue }
            binding.isActive = true
            bindings[name] = binding
            actions.append(.pressed(name))
        }
        return actions
    }

    private func matches(_ key: ResolvedKey, _ binding: Binding) -> Bool {
        if case .modifier(let triggerSided) = binding.combo.trigger {
            // Modifier triggers need an exact set, so `shift+cmd_r` and `cmd_r`
            // never both fire.
            guard case .modifier(_, let sided) = key, sided == triggerSided else { return false }
            return pressedModifiers == binding.required
        }
        guard case .trigger(let trigger) = key, trigger == binding.combo.trigger else { return false }
        return pressedModifiers.isSuperset(of: binding.combo.modifiers)
    }

    private mutating func release(_ key: ResolvedKey) -> [HotkeyAction] {
        if isCapturing { return captureRelease(key) }
        if case .modifier(let modifier, _) = key { pressedModifiers.remove(modifier) }

        var actions = deactivate { HotkeyMatcher.releases(key, $0) }
        actions += safetyNet()
        return actions
    }

    private static func releases(_ key: ResolvedKey, _ binding: Binding) -> Bool {
        switch key {
        case .modifier(let modifier, let sided):
            if case .modifier(let triggerSided) = binding.combo.trigger {
                return sided == triggerSided || binding.combo.modifiers.contains(modifier)
            }
            return binding.combo.modifiers.contains(modifier)
        case .trigger(let trigger):
            return !binding.combo.isModifierTrigger && trigger == binding.combo.trigger
        case .escape, .unknown:
            return false
        }
    }

    /// Deactivates any key-trigger binding whose modifiers are no longer held —
    /// the belt-and-braces pass for events the tap dropped.
    private mutating func safetyNet() -> [HotkeyAction] {
        let held = pressedModifiers
        return deactivate { binding in
            !binding.combo.isModifierTrigger
                && !binding.combo.modifiers.isEmpty
                && !held.isSuperset(of: binding.combo.modifiers)
        }
    }

    private mutating func deactivate(where shouldRelease: (Binding) -> Bool) -> [HotkeyAction] {
        var actions: [HotkeyAction] = []
        for name in BindingName.allCases {
            guard var binding = bindings[name], binding.isActive, shouldRelease(binding) else { continue }
            binding.isActive = false
            bindings[name] = binding
            actions.append(.released(name))
        }
        return actions
    }

    // MARK: - Capture mode (F7)

    private mutating func capturePress(_ key: ResolvedKey) -> [HotkeyAction] {
        switch key {
        case .escape:
            cancelCapture()
            return []
        case .modifier(let modifier, _):
            captureModifiers.insert(modifier)
            return []
        case .trigger(let trigger):
            guard !captureModifiers.isEmpty else { return [.captureRejected] }
            let combo = HotkeyCombo(modifiers: captureModifiers, trigger: trigger)
            isCapturing = false
            captureModifiers = []
            return [.captured(combo)]
        case .unknown:
            return []
        }
    }

    private mutating func captureRelease(_ key: ResolvedKey) -> [HotkeyAction] {
        guard case .modifier(let modifier, let sided) = key,
              captureModifiers.contains(modifier) else { return [] }
        captureModifiers.remove(modifier)
        // Only right-hand modifiers are expressible as triggers (F5).
        guard let sided else { return [.captureRejected] }
        let combo = HotkeyCombo(modifiers: captureModifiers, trigger: .modifier(sided))
        isCapturing = false
        captureModifiers = []
        return [.captured(combo)]
    }
}
