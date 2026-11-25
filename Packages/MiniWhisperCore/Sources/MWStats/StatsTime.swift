import Foundation

/// Times in `stats/`. Day keys and timestamps are Gregorian whatever the calendar passed in,
/// which only supplies the time zone, so they sort and parse alike on every Mac.
public enum StatsTime {
    /// The calendar day keys are written in, for their weekdays, month lengths and arithmetic.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Midnight UTC of a `yyyy-MM-dd` key in `utc`; nil when the key is malformed.
    static func date(ofDay key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// `yyyy-MM-dd` of the local day `date` falls on.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let local = wallClock(date, offset: calendar.timeZone.secondsFromGMT(for: date))
        return String(format: "%04d-%02d-%02d", local.year!, local.month!, local.day!)
    }

    public static func hour(_ date: Date, calendar: Calendar) -> Int {
        wallClock(date, offset: calendar.timeZone.secondsFromGMT(for: date)).hour!
    }

    /// `2026-11-30T09:14:03+00:00`: whole seconds of local time and the offset, never `Z`, so
    /// every row has one shape.
    public static func iso(_ date: Date, timeZone: TimeZone) -> String {
        let offset = timeZone.secondsFromGMT(for: date)
        let local = wallClock(date, offset: offset)
        let minutes = abs(offset) / 60
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d%@%02d:%02d",
            local.year!, local.month!, local.day!, local.hour!, local.minute!, local.second!,
            offset < 0 ? "-" : "+", minutes / 60, minutes % 60
        )
    }

    /// The instant and its offset in seconds east of UTC, from the shape `iso` writes; nil for
    /// any other.
    public static func parse(_ text: String) -> (date: Date, offset: Int)? {
        let bytes = Array(text.utf8)
        guard bytes.count == 25 else { return nil }
        func number(_ start: Int, _ length: Int) -> Int? {
            var value = 0
            for byte in bytes[start..<start + length] {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            return value
        }
        guard separators.allSatisfy({ bytes[$0.index] == $0.byte }),
              bytes[19] == UInt8(ascii: "+") || bytes[19] == UInt8(ascii: "-"),
              let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
              let offsetHours = number(20, 2), let offsetMinutes = number(23, 2),
              let wall = utc.date(from: DateComponents(
                  year: year, month: month, day: day, hour: hour, minute: minute, second: second
              ))
        else { return nil }
        let offset = (bytes[19] == UInt8(ascii: "-") ? -1 : 1) * (offsetHours * 3600 + offsetMinutes * 60)
        return (wall.addingTimeInterval(-Double(offset)), offset)
    }

    private static let separators: [(index: Int, byte: UInt8)] = [
        (4, UInt8(ascii: "-")), (7, UInt8(ascii: "-")), (10, UInt8(ascii: "T")),
        (13, UInt8(ascii: ":")), (16, UInt8(ascii: ":")), (22, UInt8(ascii: ":")),
    ]

    /// The start of the local day 13 calendar months before `now`. A month too short for the day
    /// clamps to its last day, so 31 March gives 28 February.
    public static func dictationCutoff(now: Date, calendar: Calendar) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.startOfDay(for: gregorian.date(byAdding: .month, value: -13, to: now) ?? now)
    }

    private static func wallClock(_ date: Date, offset: Int) -> DateComponents {
        let shifted = Date(timeIntervalSince1970: (date.timeIntervalSince1970 + Double(offset)).rounded(.down))
        return utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: shifted)
    }
}
