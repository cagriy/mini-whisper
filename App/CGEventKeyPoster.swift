import CoreGraphics
import MWPaste
import MWSupport

/// F25's key posting: synthetic events go to the resolved pid only, never to the
/// session tap (§5.8).
struct CGEventKeyPoster: KeyPoster {
    func post(keyCode: CGKeyCode, flags: CGEventFlags, down: Bool, pid: pid_t) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
        else {
            Log.paste.error("Could not create a synthetic key event for key \(keyCode)")
            return
        }
        event.flags = flags
        event.postToPid(pid)
    }
}
