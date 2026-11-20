import Testing

@testable import MWConfig

@Suite struct VoiceSettingsTests {
    private static let tolerance = 1e-9

    @Test func defaultsMatchTheDesign() {
        let settings = VoiceSettings()

        #expect(settings.localEnabled == false)
        #expect(settings.speechmaticsEnabled == false)
        #expect(settings.sureThreshold == 0.70)
        #expect(settings.suggestionThreshold == 0.50)
        #expect(settings.margin == 0.10)
        #expect(settings.minimumSpeechSeconds == 15)
        #expect(settings.bufferSeconds == 120)
        #expect(settings.speechmaticsSensitivity == 0.80)
        #expect(settings.step == 5)
        #expect(settings.tuned(toStep: 5) == settings)
    }

    @Test(arguments: 0...10)
    func eachStepSetsItsFiveValues(step: Int) {
        var start = VoiceSettings()
        start.localEnabled = true
        start.bufferSeconds = 240
        let tuned = start.tuned(toStep: step)
        let s = Double(step)

        #expect(abs(tuned.sureThreshold - (0.80 - 0.02 * s)) < Self.tolerance)
        #expect(abs(tuned.suggestionThreshold - (0.60 - 0.02 * s)) < Self.tolerance)
        #expect(abs(tuned.margin - (0.15 - 0.01 * s)) < Self.tolerance)
        #expect(abs(tuned.minimumSpeechSeconds - (25 - 2 * s)) < Self.tolerance)
        #expect(abs(tuned.speechmaticsSensitivity - (0.95 - 0.03 * s)) < Self.tolerance)
        #expect(tuned.localEnabled == true)
        #expect(tuned.speechmaticsEnabled == false)
        #expect(tuned.bufferSeconds == 240)
        #expect(tuned.step == step)
    }

    @Test func aStepOffTheSliderTakesTheNearestEnd() {
        #expect(VoiceSettings().tuned(toStep: -3).step == 0)
        #expect(VoiceSettings().tuned(toStep: 14).step == 10)
    }

    @Test func stepIsNilOffTheGrid() {
        var settings = VoiceSettings()

        settings.sureThreshold = 0.704
        #expect(settings.step == 5)
        settings.sureThreshold = 0.706
        #expect(settings.step == nil)

        settings = VoiceSettings()
        settings.minimumSpeechSeconds = 15.4
        #expect(settings.step == 5)
        settings.minimumSpeechSeconds = 15.6
        #expect(settings.step == nil)
    }

    @Test func theBufferIsNotOnTheSlider() {
        var settings = VoiceSettings()
        settings.bufferSeconds = 300

        #expect(settings.step == 5)
    }

    @Test func validatedClampsEachField() {
        var high = VoiceSettings()
        high.sureThreshold = 0.99
        high.suggestionThreshold = 0.99
        high.margin = 0.5
        high.minimumSpeechSeconds = 90
        high.bufferSeconds = 900
        high.speechmaticsSensitivity = 1.5
        let highValidated = high.validated()

        #expect(highValidated.sureThreshold == 0.95)
        #expect(highValidated.suggestionThreshold == 0.90)
        #expect(highValidated.margin == 0.30)
        #expect(highValidated.minimumSpeechSeconds == 60)
        #expect(highValidated.bufferSeconds == 300)
        #expect(highValidated.speechmaticsSensitivity == 1)

        var low = VoiceSettings()
        low.sureThreshold = 0.1
        low.suggestionThreshold = 0.1
        low.margin = -0.2
        low.minimumSpeechSeconds = 1
        low.bufferSeconds = 10
        low.speechmaticsSensitivity = -1
        let lowValidated = low.validated()

        #expect(lowValidated.sureThreshold == 0.50)
        #expect(lowValidated.suggestionThreshold == 0.30)
        #expect(lowValidated.margin == 0)
        #expect(lowValidated.minimumSpeechSeconds == 5)
        #expect(lowValidated.bufferSeconds == 60)
        #expect(lowValidated.speechmaticsSensitivity == 0)
    }

    @Test func theSuggestionThresholdNeverExceedsTheSureThreshold() {
        var settings = VoiceSettings()
        settings.suggestionThreshold = 0.85

        #expect(settings.validated().suggestionThreshold == 0.70)
        #expect(settings.validated().sureThreshold == 0.70)
    }

    @Test func validatedLeavesInRangeValuesAndSwitchesAlone() {
        var settings = VoiceSettings().tuned(toStep: 8)
        settings.localEnabled = true
        settings.speechmaticsEnabled = true

        #expect(settings.validated() == settings)
    }

    @Test func eachEngineHasItsRoute() {
        #expect(MeetingEngine.speechmaticsStandard.voiceRoute == .speechmatics)
        #expect(MeetingEngine.speechmaticsEnhanced.voiceRoute == .speechmatics)
        #expect(MeetingEngine.assemblyaiStreaming.voiceRoute == .local)
        #expect(MeetingEngine.assemblyaiPro.voiceRoute == .local)

        var settings = VoiceSettings()
        settings.localEnabled = true
        #expect(settings.isEnabled(.local))
        #expect(!settings.isEnabled(.speechmatics))

        settings = VoiceSettings()
        settings.speechmaticsEnabled = true
        #expect(!settings.isEnabled(.local))
        #expect(settings.isEnabled(.speechmatics))
    }

    @Test func routesHaveTheSidecarsRawValues() {
        #expect(VoiceRoute.local.rawValue == "local")
        #expect(VoiceRoute.speechmatics.rawValue == "speechmatics")
    }

    @Test func fieldRangesAndValues() {
        #expect(VoiceSettings.Field.allCases == [.sure, .suggestion, .margin, .minimumSpeech, .buffer, .sensitivity])
        #expect(VoiceSettings.range(of: .sure) == 0.50...0.95)
        #expect(VoiceSettings.range(of: .suggestion) == 0.30...0.90)
        #expect(VoiceSettings.range(of: .margin) == 0...0.30)
        #expect(VoiceSettings.range(of: .minimumSpeech) == 5...60)
        #expect(VoiceSettings.range(of: .buffer) == 60...300)
        #expect(VoiceSettings.range(of: .sensitivity) == 0...1)

        let settings = VoiceSettings()
        #expect(settings.value(of: .sure) == 0.70)
        #expect(settings.value(of: .suggestion) == 0.50)
        #expect(settings.value(of: .margin) == 0.10)
        #expect(settings.value(of: .minimumSpeech) == 15)
        #expect(settings.value(of: .buffer) == 120)
        #expect(settings.value(of: .sensitivity) == 0.80)

        let fields = VoiceSettings.Field.allCases
        #expect(fields.map { settings.setting($0, to: -1000).value(of: $0) } == [0.50, 0.30, 0, 5, 60, 0])
        #expect(fields.map { settings.setting($0, to: 1000).value(of: $0) } == [0.95, 0.70, 0.30, 60, 300, 1])
    }

    @Test(arguments: VoiceSettings.Field.allCases)
    func settingAFieldWritesOnlyThatField(field: VoiceSettings.Field) {
        let range = VoiceSettings.range(of: field)
        let inside = range.lowerBound + (range.upperBound - range.lowerBound) * 0.4
        let set = VoiceSettings().setting(field, to: inside)

        #expect(set != VoiceSettings())
        #expect(set.value(of: field) == inside)
        for other in VoiceSettings.Field.allCases where other != field {
            #expect(set.value(of: other) == VoiceSettings().value(of: other), "\(other)")
        }
    }

    @Test func loweringTheSureThresholdBelowTheSuggestionLowersTheSuggestion() {
        let suggesting = VoiceSettings().setting(.suggestion, to: 0.60)
        #expect(suggesting.suggestionThreshold == 0.60)

        let lowered = suggesting.setting(.sure, to: 0.55)
        #expect(lowered.sureThreshold == 0.55)
        #expect(lowered.suggestionThreshold == 0.55)
    }
}
