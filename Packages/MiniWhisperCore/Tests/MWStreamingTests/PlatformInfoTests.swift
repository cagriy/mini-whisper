import Foundation
import Testing

import MWStreaming

/// R2: remote meetings need a Core Audio process tap, which macOS 14.2 introduced.
@Suite struct PlatformInfoTests {
    @Test(arguments: [(14, 1, false), (14, 2, true), (15, 0, true), (26, 0, true)])
    func supportsSystemAudio(_ major: Int, _ minor: Int, _ expected: Bool) {
        #expect(PlatformInfo(osMajor: major, osMinor: minor).supportsSystemAudio == expected)
    }

    @Test func osMinorDefaultsToTheRunningSystem() {
        let running = ProcessInfo.processInfo.operatingSystemVersion

        #expect(PlatformInfo().osMinor == running.minorVersion)
        #expect(PlatformInfo(osMajor: 15, locale: Locale(identifier: "en_US")).osMinor == running.minorVersion)
    }
}
