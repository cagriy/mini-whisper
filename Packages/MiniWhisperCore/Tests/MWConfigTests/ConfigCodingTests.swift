import Foundation
import Testing
@testable import MWConfig

@Suite struct ConfigCodingTests {
    /// The seven keys `config.py:DEFAULT_CONFIG` writes.
    private static let pythonDefaultsJSON = """
        {
          "hotkey": "shift+cmd_r",
          "submit_hotkey": "cmd_r",
          "cleanup_enabled": true,
          "sound_volume": 1.0,
          "streaming_enabled": true,
          "streaming_engine": "on_device",
          "pricing_overrides": {}
        }
        """

    private func decode(_ json: String) throws -> Config {
        try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    }

    @Test func decodesPythonDefaultsExactly() throws {
        let config = try decode(Self.pythonDefaultsJSON)

        #expect(config.hotkey == "shift+cmd_r")
        #expect(config.submitHotkey == "cmd_r")
        #expect(config.cleanupEnabled)
        #expect(config.soundVolume == 1.0)
        #expect(config.streamingEnabled)
        #expect(config.streamingEngine == .onDevice)
        #expect(config.pricingOverrides.isEmpty)
    }

    @Test func decodesNewKeysWithDefaults() throws {
        let config = try decode(Self.pythonDefaultsJSON)

        #expect(config.historyRetentionDays == 7)
        #expect(config.idleStopSeconds == 60)
        #expect(config.toggleMaxSeconds == 300)
        #expect(config.vocabulary == [])
        #expect(config.profiles == [])
        #expect(config.speechModelPrompted == false)
    }

    @Test func preservesUnknownKeysOnRoundTrip() throws {
        let json = """
            {"hotkey": "cmd+space", "future_flag": true, "future_count": 3,
             "future_nested": {"a": [1, "two", null], "b": 1.5}}
            """
        let config = try decode(json)

        let object = try #require(
            JSONSerialization.jsonObject(with: config.encoded()) as? [String: Any]
        )
        #expect(object["future_flag"] as? Bool == true)
        #expect(object["future_count"] as? Int == 3)
        let nested = try #require(object["future_nested"] as? [String: Any])
        #expect(nested["a"] as? [Any] != nil)
        #expect(nested["b"] as? Double == 1.5)
        #expect(object["hotkey"] as? String == "cmd+space")
    }

    @Test func clampsBounds() throws {
        let high = try decode(
            #"{"history_retention_days": 99, "idle_stop_seconds": 9999, "toggle_max_seconds": 9999}"#
        ).validated()
        #expect(high.historyRetentionDays == 30)
        #expect(high.idleStopSeconds == 600)
        #expect(high.toggleMaxSeconds == 1800)

        let low = try decode(
            #"{"history_retention_days": -5, "idle_stop_seconds": 1, "toggle_max_seconds": 1}"#
        ).validated()
        #expect(low.historyRetentionDays == 0)
        #expect(low.idleStopSeconds == 10)
        #expect(low.toggleMaxSeconds == 60)
    }

    @Test func unknownSubmitKeyBecomesEnter() throws {
        let json = """
            {"profiles": [{"id": "1", "name": "Terminal", "bundle_ids": [],
              "cleanup_enabled": true, "submit_key": "double_enter", "cleanup_prompt": null}]}
            """
        #expect(try decode(json).profiles.first?.submitKey == .enter)
    }

    @Test func unrecognisedStreamingEngineIsIgnoredButPreserved() throws {
        // A value written by a newer build: not honoured here, but F2 forbids
        // destroying it on the next save.
        let config = try decode(#"{"streaming_engine": "future_engine"}"#)
        #expect(config.streamingEngine == nil)

        let saved = try JSONSerialization.jsonObject(with: config.encoded()) as? [String: Any]
        #expect(saved?["streaming_engine"] as? String == "future_engine")
    }

    @Test func chosenStreamingEngineReplacesAnUnrecognisedOne() throws {
        var config = try decode(#"{"streaming_engine": "future_engine"}"#)
        config.streamingEngine = .openai

        let saved = try JSONSerialization.jsonObject(with: config.encoded()) as? [String: Any]
        #expect(saved?["streaming_engine"] as? String == "openai")
    }

    @Test func duplicateBundleIDKeepsFirstProfile() throws {
        let json = """
            {"profiles": [
              {"id": "1", "name": "Terminal", "bundle_ids": ["com.apple.Terminal", "com.apple.Terminal"],
               "cleanup_enabled": false, "submit_key": "enter", "cleanup_prompt": null},
              {"id": "2", "name": "Slack", "bundle_ids": ["com.apple.Terminal", "com.tinyspeck.slackmacgap"],
               "cleanup_enabled": true, "submit_key": "cmd_enter", "cleanup_prompt": null}]}
            """
        let config = try decode(json).validated()

        #expect(config.profiles.count == 2)
        #expect(config.profiles.first?.bundleIDs == ["com.apple.Terminal"])
        #expect(config.profiles.last?.bundleIDs == ["com.tinyspeck.slackmacgap"])
    }

    @Test func streamingEngineAbsentIsNil() throws {
        #expect(try decode("{}").streamingEngine == nil)
    }

    @Test func speechAnalyzerIsAValidEngine() throws {
        #expect(try decode(#"{"streaming_engine": "speech_analyzer"}"#).streamingEngine == .speechAnalyzer)
        #expect(
            EngineName.allCases.map(\.rawValue)
                == ["speech_analyzer", "on_device", "openai", "elevenlabs", "speechmatics"]
        )
    }

    @Test func writesTwoSpaceIndentWithTrailingNewline() throws {
        let text = String(decoding: try Config().encoded(), as: UTF8.self)

        #expect(text.hasSuffix("}\n"))
        #expect(text.hasPrefix("{\n  \""))
        #expect(!text.contains("\n    \"hotkey"))
    }

    @Test func usageDictionaryRoundTrips() throws {
        let json = """
            {"usage": {"2026-09-01": {"input_tokens": 20, "output_tokens": 30,
              "streamed_seconds": {"on_device": 60.0}, "cost_usd": 0.05}}}
            """
        let config = try decode(json)
        #expect(
            config.usage["2026-09-01"]
                == DayUsage(
                    inputTokens: 20, outputTokens: 30,
                    streamedSeconds: ["on_device": 60.0], costUSD: 0.05
                )
        )

        let reloaded = try decode(String(decoding: config.encoded(), as: UTF8.self))
        #expect(reloaded.usage == config.usage)
    }

    /// N6: the Python app must still be able to read what this app writes.
    @Test func pythonReadableKeysAndTypes() throws {
        let object = try #require(
            JSONSerialization.jsonObject(with: Config().encoded()) as? [String: Any]
        )

        #expect(object["hotkey"] as? String == "shift+cmd_r")
        #expect(object["submit_hotkey"] as? String == "cmd_r")
        // Written only once chosen; absent leaves F32's default in charge.
        #expect(!object.keys.contains("streaming_engine"))
        #expect(CFGetTypeID(try #require(object["cleanup_enabled"] as CFTypeRef?)) == CFBooleanGetTypeID())
        #expect(CFGetTypeID(try #require(object["streaming_enabled"] as CFTypeRef?)) == CFBooleanGetTypeID())
        #expect(object["sound_volume"] as? Double == 1.0)
        #expect(object["pricing_overrides"] as? [String: Double] == [:])
    }

    @Test func decodesCorrectionsAndTally() throws {
        let json = """
            {"corrections": [
               {"id": "b2e7", "heard": "eefa", "write": "Aoife", "sounds_like": ["eefa", "eva"],
                "bundle_id": "com.tinyspeck.slackmacgap", "enabled": true},
               {"id": "9c10", "heard": "get hub", "write": "GitHub", "sounds_like": ["get hub"],
                "bundle_id": null, "enabled": false}],
             "correction_tally": [
               {"heard": "eefa", "count": 4, "last": "2026-09-05T16:07:00Z"}]}
            """
        let config = try decode(json)

        #expect(
            config.corrections == [
                CorrectionRule(
                    id: "b2e7", heard: "eefa", write: "Aoife", soundsLike: ["eefa", "eva"],
                    bundleID: "com.tinyspeck.slackmacgap", enabled: true
                ),
                CorrectionRule(
                    id: "9c10", heard: "get hub", write: "GitHub", soundsLike: ["get hub"],
                    bundleID: nil, enabled: false
                ),
            ]
        )
        #expect(
            config.correctionTally == [
                CorrectionTallyEntry(
                    heard: "eefa", count: 4,
                    last: ISO8601DateFormatter.mwConfig.date(from: "2026-09-05T16:07:00Z")!
                )
            ]
        )
    }

    @Test func correctionDefaultsOnDecode() throws {
        let config = try decode(#"{"corrections": [{"heard": "eefa", "write": "Aoife"}]}"#)

        let rule = try #require(config.corrections.first)
        #expect(UUID(uuidString: rule.id) != nil)
        #expect(rule.soundsLike == [])
        #expect(rule.enabled)
        #expect(rule.bundleID == nil)
    }

    @Test func correctionsRoundTripWithExplicitNullBundleID() throws {
        var config = Config()
        config.corrections = [CorrectionRule(id: "9c10", heard: "get hub", write: "GitHub")]
        config.correctionTally = [
            CorrectionTallyEntry(
                heard: "get hub", count: 2,
                last: try #require(ISO8601DateFormatter.mwConfig.date(from: "2026-09-04T09:12:41Z"))
            )
        ]

        let object = try #require(
            JSONSerialization.jsonObject(with: config.encoded()) as? [String: Any]
        )
        let rule = try #require((object["corrections"] as? [[String: Any]])?.first)
        #expect(rule["bundle_id"] is NSNull)
        #expect(rule["heard"] as? String == "get hub")
        #expect(rule["sounds_like"] as? [String] == [])
        #expect(CFGetTypeID(try #require(rule["enabled"] as CFTypeRef?)) == CFBooleanGetTypeID())
        let entry = try #require((object["correction_tally"] as? [[String: Any]])?.first)
        #expect(entry["last"] as? String == "2026-09-04T09:12:41Z")
        #expect(entry["count"] as? Int == 2)

        let reloaded = try decode(String(decoding: config.encoded(), as: UTF8.self))
        #expect(reloaded.corrections == config.corrections)
        #expect(reloaded.correctionTally == config.correctionTally)
    }

    @Test func correctionKeysNeverLandInExtra() throws {
        let config = try decode(
            #"{"corrections": [{"heard": "a", "write": "b"}], "correction_tally": []}"#
        )

        #expect(config.extra["corrections"] == nil)
        #expect(config.extra["correction_tally"] == nil)
    }

    @Test func malformedTallyTimestampDecodesAsDistantPast() throws {
        let config = try decode(
            #"{"correction_tally": [{"heard": "eefa", "count": 1, "last": "yesterday"}]}"#
        )

        #expect(config.correctionTally.first?.last == .distantPast)
    }

    @Test func validatedNormalisesAndDropsInvalidRules() throws {
        let json = """
            {"corrections": [
               {"id": "1", "heard": "  get   hub ", "write": " Git  Hub ",
                "sounds_like": ["  get  hub ", "   ", ""], "bundle_id": null, "enabled": true},
               {"id": "2", "heard": "get hub", "write": "GitHub", "bundle_id": null, "enabled": true},
               {"id": "3", "heard": "get hub", "write": "GitHub",
                "bundle_id": "com.tinyspeck.slackmacgap", "enabled": true},
               {"id": "4", "heard": "   ", "write": "GitHub", "bundle_id": null, "enabled": true},
               {"id": "5", "heard": "eefa", "write": "  ", "bundle_id": null, "enabled": true}]}
            """
        let config = try decode(json).validated()

        #expect(config.corrections.map(\.id) == ["1", "3"])
        let first = try #require(config.corrections.first)
        #expect(first.heard == "get hub")
        #expect(first.write == "Git Hub")
        #expect(first.soundsLike == ["get hub"])
    }

    @Test func phraseKeyNormalisesAndLowercases() {
        #expect(PhraseKey.normalised("  Get   Hub\n") == "Get Hub")
        #expect(PhraseKey.normalised("e\u{0301}efa") == "\u{00E9}efa")
        #expect(PhraseKey.key("  Get   Hub ") == "get hub")
        #expect(PhraseKey.key("") == "")
    }
}
