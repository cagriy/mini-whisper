import Foundation
import MWConfig
import MWSupport

/// Dictation cost maths and the two menu rows (F35, F31), a port of
/// `../mini-whisper-py/src/mini_whisper/pricing.py` with the added `speech_analyzer` rate.
/// Every constant is overridable through `config.json`'s `pricing_overrides`.
public enum Pricing {
    public static let perMinute: [String: Double] = [
        "openai_realtime": 0.017,
        "elevenlabs": 0.0065,
        "speechmatics": 0.0067,
        "on_device": 0.0,
        "speech_analyzer": 0.0,
    ]

    public static let perMTok: [String: Double] = [
        "gpt-4o-mini-transcribe_in": 1.25,
        "gpt-4o-mini-transcribe_out": 5.00,
        "gpt-4o-mini_in": 0.15,
        "gpt-4o-mini_out": 0.60,
    ]

    /// Engine names whose rate-table key differs from the name.
    private static let engineRateKeys: [EngineName: String] = [.openai: "openai_realtime"]

    public static func rate(
        _ table: [String: Double],
        key: String,
        overrides: [String: Double] = [:]
    ) -> Double {
        overrides[key] ?? table[key] ?? 0
    }

    /// `engine` is the streaming engine billed for `seconds` (nil = batch only);
    /// `tokensByModel` bills the OpenAI models the dictation used.
    public static func dictationCost(
        engine: EngineName?,
        seconds: TimeInterval,
        tokensByModel: [String: TokenUsage],
        overrides: [String: Double] = [:]
    ) -> Double {
        var cost = 0.0
        if let engine {
            let key = engineRateKeys[engine] ?? engine.rawValue
            cost += (seconds / 60) * rate(perMinute, key: key, overrides: overrides)
        }
        // Sorted so the floating-point sum does not depend on dictionary order.
        for model in tokensByModel.keys.sorted() {
            guard let tokens = tokensByModel[model] else { continue }
            cost += Double(tokens.inputTokens) / 1_000_000
                * rate(perMTok, key: "\(model)_in", overrides: overrides)
            cost += Double(tokens.outputTokens) / 1_000_000
                * rate(perMTok, key: "\(model)_out", overrides: overrides)
        }
        return (cost * 1_000_000).rounded() / 1_000_000
    }

    /// The two menu rows (F31): `Today: 1.2k/340 tok · 3m · $0.12` and `Month: $1.50`.
    public static func formatUsageRows(
        today: DayEntry,
        monthCost: Double
    ) -> (today: String, month: String) {
        let minutes = Int((today.streamedSeconds.values.reduce(0, +) / 60).rounded(.down))
        let todayRow = "Today: \(tokens(today.inputTokens))/\(tokens(today.outputTokens)) tok"
            + " · \(minutes)m · \(dollars(today.costUSD))"
        return (todayRow, "Month: \(dollars(monthCost))")
    }

    private static func tokens(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fk", Double(count) / 1000) : String(count)
    }

    /// `$1.50`, or `<$0.01` when the amount is real but too small to show at this
    /// precision — a cleanup call costs about $0.00004, and `$0.000` reads as free.
    public static func dollars(_ amount: Double, decimals: Int = 2) -> String {
        let smallest = pow(10, -Double(decimals))
        if amount > 0, amount < smallest / 2 {
            return String(format: "<$%.\(decimals)f", smallest)
        }
        return String(format: "$%.\(decimals)f", amount)
    }
}
