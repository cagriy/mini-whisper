import Foundation
import MWUsage

/// Figure text for Timeline and the sidebar. Values round half away from zero at the precision
/// shown, before the form is chosen, so a value that rounds up to the next form takes it:
/// 999,950 on the page reads `1M`, never `1000k`.
public enum StatFormat {
    /// Grouped below 10,000, then `86.4k`, then `1.42M`.
    public static func pageNumber(_ value: Double, locale: Locale = .current) -> String {
        compact(value, page, locale: locale)
    }

    public static func pageNumber(_ value: Int, locale: Locale = .current) -> String {
        pageNumber(Double(value), locale: locale)
    }

    /// Plain below 1,000, then `8.4k`, `126k` from 100k, then `1.4M`.
    public static func sidebarNumber(_ value: Double, locale: Locale = .current) -> String {
        compact(value, sidebar, locale: locale)
    }

    public static func sidebarNumber(_ value: Int, locale: Locale = .current) -> String {
        sidebarNumber(Double(value), locale: locale)
    }

    /// `42 m` below an hour, `1 h 50 m` (`2 h` on the hour) below 10 h, `14.5 h` below 100 h,
    /// then whole hours.
    public static func duration(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let minutes = (seconds / 60).rounded(.toNearestOrAwayFromZero)
        if minutes < 60 { return "\(decimal(minutes, upTo: 0, locale: locale)) m" }
        if minutes < 600 {
            let hours = (minutes / 60).rounded(.down)
            let rest = minutes - hours * 60
            let text = "\(decimal(hours, upTo: 0, locale: locale)) h"
            return rest == 0 ? text : "\(text) \(decimal(rest, upTo: 0, locale: locale)) m"
        }
        return compact(seconds, hours, locale: locale)
    }

    public static func money(_ usd: Double) -> String {
        Pricing.dollars(usd)
    }

    /// One form of a number: `unit` and `decimals` set its precision, and it applies while the
    /// rounded value stays under `below`.
    private struct Form: Sendable {
        let unit: Double
        let decimals: Int
        let below: Double?
        let suffix: String

        var step: Double { unit / pow(10, Double(decimals)) }
    }

    private static let page = [
        Form(unit: 1, decimals: 0, below: 10_000, suffix: ""),
        Form(unit: 1_000, decimals: 1, below: 1_000_000, suffix: "k"),
        Form(unit: 1_000_000, decimals: 2, below: nil, suffix: "M"),
    ]

    private static let sidebar = [
        Form(unit: 1, decimals: 0, below: 1_000, suffix: ""),
        Form(unit: 1_000, decimals: 1, below: 100_000, suffix: "k"),
        Form(unit: 1_000, decimals: 0, below: 1_000_000, suffix: "k"),
        Form(unit: 1_000_000, decimals: 1, below: nil, suffix: "M"),
    ]

    private static let hours = [
        Form(unit: 3_600, decimals: 1, below: 360_000, suffix: " h"),
        Form(unit: 3_600, decimals: 0, below: nil, suffix: " h"),
    ]

    private static func compact(_ value: Double, _ forms: [Form], locale: Locale) -> String {
        for form in forms {
            let rounded = (value / form.step).rounded(.toNearestOrAwayFromZero) * form.step
            if form.below.map({ rounded < $0 }) ?? true {
                return decimal(rounded / form.unit, upTo: form.decimals, locale: locale) + form.suffix
            }
        }
        return ""
    }

    private static func decimal(_ value: Double, upTo decimals: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(0...decimals)))
    }
}
