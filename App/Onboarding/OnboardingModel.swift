import Foundation

/// The two TCC grants the wizard walks through, in the source's order
/// (`onboarding.py:PERM_ORDER`).
enum OnboardingPermission: String, CaseIterable, Hashable {
    case microphone
    case accessibility

    var label: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        }
    }

    var symbolName: String {
        switch self {
        case .microphone: "mic.fill"
        case .accessibility: "keyboard.fill"
        }
    }

    var settingsURL: URL {
        let pane: String
        switch self {
        case .microphone: pane = "Privacy_Microphone"
        case .accessibility: pane = "Privacy_Accessibility"
        }
        // Force-unwrapped: both strings are literals and always parse.
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}

/// The onboarding wizard's state (F33), free of AppKit so the step advance, the
/// request order and the status text are host-tested. A port of
/// `onboarding.py:_advance_to_next_ungranted`, `_poll` and `_update_indicators`.
///
/// Grants are sampled once per `start()`/`poll()` so every label in one refresh
/// agrees, as the source's single pass over the checkers does.
struct OnboardingModel {
    static let steps = OnboardingPermission.allCases

    private let isGranted: (OnboardingPermission) -> Bool
    private let request: (OnboardingPermission) -> Void
    private var sampled: [OnboardingPermission: Bool] = [:]

    private(set) var currentStep = 0

    init(
        isGranted: @escaping (OnboardingPermission) -> Bool,
        request: @escaping (OnboardingPermission) -> Void
    ) {
        self.isGranted = isGranted
        self.request = request
    }

    func granted(_ permission: OnboardingPermission) -> Bool {
        sampled[permission] ?? false
    }

    var allGranted: Bool {
        Self.steps.allSatisfy(granted)
    }

    var continueEnabled: Bool { allGranted }

    var statusText: String {
        if allGranted { return "All permissions granted!" }
        guard currentStep < Self.steps.count else { return "Grant all permissions to continue." }
        return "Please grant \(Self.steps[currentStep].label) access."
    }

    /// Skips the steps already granted, then triggers the system prompt for the
    /// first ungranted one only.
    mutating func start() {
        advancePastGranted()
        requestCurrent()
        sample()
    }

    /// The 1.5 s timer tick: advance when the step the user is on has been granted.
    mutating func poll() {
        sample()
        guard currentStep < Self.steps.count, isGranted(Self.steps[currentStep]) else { return }
        currentStep += 1
        advancePastGranted()
        requestCurrent()
        sample()
    }

    private mutating func advancePastGranted() {
        while currentStep < Self.steps.count, isGranted(Self.steps[currentStep]) {
            currentStep += 1
        }
    }

    private func requestCurrent() {
        guard currentStep < Self.steps.count else { return }
        request(Self.steps[currentStep])
    }

    private mutating func sample() {
        sampled = Dictionary(uniqueKeysWithValues: Self.steps.map { ($0, isGranted($0)) })
    }
}
