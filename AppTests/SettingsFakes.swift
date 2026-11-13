import MWConfig
import MWHotkeys
@testable import MiniWhisper

/// The seams a `SettingsModel` is built over, for every suite that needs one.
final class FakeSecrets: SecretStore, @unchecked Sendable {
    var stored: [KeyAccount: String] = [:]

    func secret(for account: KeyAccount) throws -> String? { stored[account] }
    func setSecret(_ secret: String, for account: KeyAccount) throws { stored[account] = secret }
    func removeSecret(for account: KeyAccount) throws { stored[account] = nil }
}

final class FakeHotkeys: HotkeyCapturing, @unchecked Sendable {
    var begun = 0
    var cancelled = 0
    var updates: [BindingName: HotkeyCombo] = [:]

    func beginCapture() { begun += 1 }
    func cancelCapture() { cancelled += 1 }
    func update(binding: BindingName, combo: HotkeyCombo) { updates[binding] = combo }
}

final class FakeSounds: SoundPreviewing, @unchecked Sendable {
    var volume: Float = -1
    var onPlays = 0

    func setVolume(_ volume: Float) { self.volume = volume }
    func playOn() { onPlays += 1 }
}

final class FakeUpdater: UpdateChecking, @unchecked Sendable {
    var automaticallyChecksForUpdates = true
    var checks = 0

    func checkForUpdates() { checks += 1 }
}
