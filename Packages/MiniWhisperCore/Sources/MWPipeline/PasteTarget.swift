import Foundation

/// The frontmost application as captured at release time (F17): where the text goes and
/// what the history entry records.
public struct PasteTarget: Sendable, Equatable {
    public var pid: pid_t
    public var name: String
    public var bundleID: String?

    public init(pid: pid_t, name: String, bundleID: String? = nil) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
    }
}
