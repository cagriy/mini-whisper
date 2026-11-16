import Foundation
import Observation

/// What the silence prompt shows (design v7 §5.3), re-sent every second while it counts down.
@MainActor
@Observable
final class SilencePromptModel {
    private static let countdown = 60.0

    var meetingTitle = ""
    var minutes = 1
    var secondsLeft = 60
    @ObservationIgnored var onKeep: @MainActor () -> Void = {}
    @ObservationIgnored var onStop: @MainActor () -> Void = {}

    /// "Recording" alone when the user cleared the title.
    var eyebrow: String {
        let title = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Recording" : "Recording · \(title)"
    }

    var title: String {
        "No one has spoken for \(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }

    var countdownText: String {
        "\(secondsLeft / 60):" + String(format: "%02d", secondsLeft % 60)
    }

    /// The meter's filled share.
    var fraction: Double { Double(secondsLeft) / Self.countdown }

    func keep() { onKeep() }
    func stop() { onStop() }
}
