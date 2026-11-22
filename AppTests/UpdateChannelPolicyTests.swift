import MWConfig
import Testing
@testable import MiniWhisper

@Suite struct UpdateChannelPolicyTests {
    @Test func sparkleChannelsFollowTheChannel() {
        #expect(UpdateChannelPolicy.sparkleChannels(for: .release) == [])
        #expect(UpdateChannelPolicy.sparkleChannels(for: .beta) == ["beta"])
    }

    @Test(arguments: ["0.9.0b1", "1.10.2b12"])
    func isBetaRecognisesBetaVersions(version: String) {
        #expect(UpdateChannelPolicy.isBeta(version: version))
    }

    @Test(arguments: ["0.8.2", "0.9.0-beta.1", "0.9.0b", "0.9.0rc1", ""])
    func isBetaRejectsEverythingElse(version: String) {
        #expect(!UpdateChannelPolicy.isBeta(version: version))
    }

    @Test func trackerReportsOnlyChangesAfterTheFirst() {
        var tracker = UpdateChannelPolicy.Tracker()
        let changes = [UpdateChannel.release, .release, .beta, .release].map { tracker.apply($0) }
        #expect(changes == [false, false, true, true])

        var startsOnBeta = UpdateChannelPolicy.Tracker()
        let first = startsOnBeta.apply(.beta)
        #expect(!first)
    }
}
