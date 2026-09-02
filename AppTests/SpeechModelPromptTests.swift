import Foundation
import MWStreaming
import Testing
@testable import MiniWhisper

@Suite struct SpeechModelPromptTests {
    private final class Recorder: @unchecked Sendable {
        var installs = 0
        var marked = 0
    }

    private func prompt(_ recorder: Recorder) -> SpeechModelPrompt {
        SpeechModelPrompt(
            install: { recorder.installs += 1 },
            markPrompted: { recorder.marked += 1 }
        )
    }

    @Test(arguments: [
        (26, AssetStatus.notInstalled, false, true),
        (14, AssetStatus.notInstalled, false, false),
        (26, AssetStatus.unavailable, false, false),
        (26, AssetStatus.installed, false, false),
        (26, AssetStatus.installing(fractionCompleted: 0.5), false, false),
        (26, AssetStatus.notInstalled, true, false),
    ])
    func promptsOnlyOn26WhenAvailableNotInstalledAndNotPrompted(
        osMajor: Int,
        status: AssetStatus,
        alreadyPrompted: Bool,
        expected: Bool
    ) {
        #expect(
            SpeechModelPrompt.shouldPrompt(
                osMajor: osMajor,
                status: status,
                alreadyPrompted: alreadyPrompted
            ) == expected
        )
    }

    @Test func eitherChoiceSetsPromptedTrue() async {
        let recorder = Recorder()
        await prompt(recorder).choose(.notNow)
        #expect(recorder.marked == 1)
        #expect(recorder.installs == 0)

        await prompt(recorder).choose(.download)
        #expect(recorder.marked == 2)
    }

    @Test func downloadTriggersInstall() async {
        let recorder = Recorder()
        await prompt(recorder).choose(.download)
        #expect(recorder.installs == 1)
        #expect(recorder.marked == 1)
    }
}
