import CoreGraphics
import MWConfig

/// Virtual key codes for the paste sequence, matching the Python `paster.py`.
enum SubmitKeyCodes {
    static let v: CGKeyCode = 9
    static let enter: CGKeyCode = 36

    static func stroke(for key: SubmitKey) -> (keyCode: CGKeyCode, flags: CGEventFlags) {
        switch key {
        case .enter: (enter, [])
        case .shiftEnter: (enter, .maskShift)
        case .cmdEnter: (enter, .maskCommand)
        }
    }
}
