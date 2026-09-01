import Foundation
import Testing
@testable import MiniWhisper

@Suite struct AppPlaceholderTests {
    @Test func bundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "com.ips.mini-whisper")
    }
}
