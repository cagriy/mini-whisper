import Foundation

/// The two facts engine selection needs about the machine (F23, F32).
public struct PlatformInfo: Sendable, Equatable {
    public var osMajor: Int
    public var locale: Locale

    public init(
        osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        locale: Locale = .current
    ) {
        self.osMajor = osMajor
        self.locale = locale
    }
}
