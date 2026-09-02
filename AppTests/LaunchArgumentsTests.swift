import Foundation
import Testing
@testable import MiniWhisper

@Suite struct LaunchArgumentsTests {
    @Test func debugFlagRecognised() {
        #expect(LaunchArguments(arguments: ["Mini Whisper", "--debug"]).debug)
        #expect(!LaunchArguments(arguments: ["Mini Whisper"]).debug)
        #expect(!LaunchArguments(arguments: ["Mini Whisper", "-debug"]).debug)
    }

    @Test func debugLogPathMatchesTheSource() {
        #expect(LaunchArguments.debugLogURL.path == "/tmp/mini-whisper.log")
    }
}
