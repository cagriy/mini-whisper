import Foundation

/// The facts engine selection needs about the machine (F23, F32), plus whether remote
/// meetings can tap system audio (R2).
public struct PlatformInfo: Sendable, Equatable {
    public var osMajor: Int
    public var osMinor: Int
    public var locale: Locale

    public init(
        osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        osMinor: Int = ProcessInfo.processInfo.operatingSystemVersion.minorVersion,
        locale: Locale = .current
    ) {
        self.osMajor = osMajor
        self.osMinor = osMinor
        self.locale = locale
    }

    /// Core Audio process taps arrived in macOS 14.2.
    public var supportsSystemAudio: Bool { osMajor > 14 || (osMajor == 14 && osMinor >= 2) }
}
