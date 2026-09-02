import CoreGraphics
import Foundation

/// One synthetic key event to a single pid. The app never posts to the session tap
/// (design §5.8), and under test nothing reaches the window server.
public protocol KeyPoster: Sendable {
    func post(keyCode: CGKeyCode, flags: CGEventFlags, down: Bool, pid: pid_t)
}
