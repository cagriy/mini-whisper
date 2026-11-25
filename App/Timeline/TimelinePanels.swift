import Foundation
import MWStats
import SwiftUI

/// Timeline's words for days, times and counts. Day keys are calendar dates, so they are read and
/// written in UTC; numbers follow the user's locale through `StatFormat`.
@MainActor
enum TimelineText {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private static var formatters: [String: DateFormatter] = [:]

    /// A `yyyy-MM-dd` key in `pattern`: "24 Nov 2026" for `d MMM yyyy`.
    static func day(_ key: String, _ pattern: String = "d MMM yyyy") -> String {
        guard let date = formatter("yyyy-MM-dd").date(from: key) else { return key }
        return formatter(pattern).string(from: date)
    }

    /// "2 Feb to 24 Feb 2027", the first year only when it differs.
    static func span(_ first: String, _ last: String) -> String {
        guard first != last else { return day(last) }
        let from = day(first, first.prefix(4) == last.prefix(4) ? "d MMM" : "d MMM yyyy")
        return "\(from) to \(day(last))"
    }

    /// Seconds after midnight as "07:05"; a finish on a later day reads past 24:00.
    static func clock(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// "1 meeting", "214 meetings".
    static func count(_ value: Int, _ one: String, _ many: String) -> String {
        "\(StatFormat.pageNumber(value)) \(value == 1 ? one : many)"
    }

    /// "Mon", for 1 Sunday to 7 Saturday.
    static func weekday(_ weekday: Int) -> String { calendar.shortWeekdaySymbols[(weekday + 6) % 7] }
    static func weekdayName(_ weekday: Int) -> String { calendar.weekdaySymbols[(weekday + 6) % 7] }
    /// "Jan" and "J", for 1 to 12.
    static func month(_ month: Int) -> String { calendar.shortMonthSymbols[(month + 11) % 12] }
    static func monthInitial(_ month: Int) -> String { calendar.veryShortMonthSymbols[(month + 11) % 12] }
    static func monthName(_ month: Int) -> String { calendar.monthSymbols[(month + 11) % 12] }

    private static func formatter(_ pattern: String) -> DateFormatter {
        if let known = formatters[pattern] { return known }
        let formatter = MeetingsListModel.formatter(pattern, calendar)
        formatters[pattern] = formatter
        return formatter
    }
}

// MARK: - 1 Lifetime totals

/// Up to five figures in `type.score` between hairlines; a zero figure is left out. Where a figure would
/// not fit its share of a narrow column they step down to `type.title`, judged on the final values so
/// the style holds while they count up.
struct TotalsPanel: View {
    let totals: TimelineReport.Totals
    let play: TimelinePlay

    @State private var width: CGFloat = 0

    private struct Figure {
        let value: Double
        let format: (Double) -> String
        let label: String
    }

    private var figures: [Figure] {
        let number: (Double) -> String = { StatFormat.pageNumber($0) }
        return [
            totals.meetings.map { Figure(value: Double($0), format: number, label: "Meetings") },
            totals.recorded.map { Figure(value: $0, format: { StatFormat.duration($0) }, label: "Recorded") },
            totals.wordsTranscribed.map { Figure(value: Double($0), format: number, label: "Words transcribed") },
            totals.dictations.map { Figure(value: Double($0), format: number, label: "Dictations") },
            totals.spend.map { Figure(value: $0, format: StatFormat.money, label: "Estimated spend") },
        ].compactMap { $0 }
    }

    var body: some View {
        let figures = figures
        let style = style(of: figures)
        TimelinePanel("Lifetime totals", showsHeading: false, play: play) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(figures.indices, id: \.self) { index in
                    if index > 0 {
                        Rectangle().fill(DS.Colors.line).frame(width: DS.Size.hairline)
                    }
                    StatFigure(figures[index].value, format: figures[index].format, label: figures[index].label, style: style)
                        .lineLimit(2)
                        .padding(EdgeInsets(
                            top: DS.Space.s7, leading: Self.leading(index), bottom: DS.Space.s6, trailing: DS.Space.s6
                        ))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .hairline(.top)
            .hairline(.bottom)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }

    private static func leading(_ index: Int) -> CGFloat { index > 0 ? DS.Space.s7 : 0 }

    private func style(of figures: [Figure]) -> DS.TextStyle {
        guard width > 0, !figures.isEmpty else { return .score }
        let share = (width - DS.Size.hairline * CGFloat(figures.count - 1)) / CGFloat(figures.count)
        let fits = figures.indices.allSatisfy { index in
            let figure = figures[index]
            let text = max(
                Self.width(of: figure.format(figure.value), Self.tabular(DS.TextStyle.score.nsFont)),
                Self.width(of: figure.label, DS.TextStyle.meta.nsFont)
            )
            return text + Self.leading(index) + DS.Space.s6 <= share
        }
        return fits ? .score : .title
    }

    private static func width(of text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    /// The font with the tabular digits `monospacedDigit()` draws the figures in.
    private static func tabular(_ font: NSFont) -> NSFont {
        let digits: [NSFontDescriptor.FeatureKey: Int] = [
            .typeIdentifier: kNumberSpacingType, .selectorIdentifier: kMonospacedNumbersSelector,
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: [digits]])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}

// MARK: - 2 The year

/// One cell a day for the shown year, by time recorded or by dictations, with the year stepper.
struct YearPanel: View {
    let year: TimelineReport.CalendarYear
    let years: ClosedRange<Int>
    let weekdays: [Int]
    /// The first year with a day of dictation, whose caption says from when.
    let firstDictationYear: Int?
    @Binding var mode: TimelineModel.Mode
    @Binding var selectedYear: Int
    let play: TimelinePlay

    private var grid: TimelineReport.YearGrid { mode == .meetings ? year.meetings : year.dictation }

    var body: some View {
        TimelinePanel("The year", play: play) {
            Spacer()
            SegmentedPill(selection: $mode, options: [(.meetings, "Meetings"), (.dictation, "Dictation")])
            StepperPill(
                title: "Year", value: $selectedYear, range: years, step: 1, label: String(year.year),
                decrease: "chevron.left", increase: "chevron.right"
            )
        } content: {
            HeatGrid(
                columns: grid.weeks.map { $0.map { $0?.level } },
                rowLabels: weekdays.map { [2, 4, 6].contains($0) ? TimelineText.weekday($0) : "" },
                columnLabels: monthLabels,
                label: "\(year.year): \(caption)",
                values: weekValues
            )
            HStack(spacing: DS.Space.s5) {
                Text(caption)
                    .textStyle(.meta)
                    .foregroundStyle(DS.Colors.textSecondary)
                Spacer()
                ChartLegend(less: "Less", more: "More")
            }
        }
    }

    private var caption: String {
        switch mode {
        case .meetings:
            let days = TimelineText.count(year.activeDays, "active day", "active days")
            guard let streak = year.longestStreak else { return days }
            return "\(days) · longest streak \(TimelineText.count(streak.days, "day", "days"))"
        case .dictation:
            let days = TimelineText.count(year.dictationDays, "day with dictation", "days with dictation")
            guard year.year == firstDictationYear,
                  let first = year.dictation.weeks.joined().compactMap({ $0 }).first(where: { $0.amount > 0 })
            else { return days }
            return "\(days), from \(TimelineText.day(first.key, "d MMM"))"
        }
    }

    /// Each month's name over the week its first day falls in.
    private var monthLabels: [Int: String] {
        var labels: [Int: String] = [:]
        for (column, week) in grid.weeks.enumerated() {
            if let first = week.compactMap({ $0 }).first(where: { $0.key.hasSuffix("-01") }),
               let month = Int(first.key.dropFirst(5).prefix(2)) {
                labels[column] = TimelineText.month(month)
            }
        }
        return labels
    }

    /// One sentence for each week with any activity.
    private var weekValues: [String] {
        grid.weeks.compactMap { week in
            let days = week.compactMap { $0 }
            let amount = days.reduce(0) { $0 + $1.amount }
            guard amount > 0, let first = days.first else { return nil }
            let total = mode == .meetings
                ? "\(StatFormat.duration(amount)) recorded"
                : TimelineText.count(Int(amount), "dictation", "dictations")
            return "Week of \(TimelineText.day(first.key, "d MMM")): \(total)"
        }
    }
}

// MARK: - 3 Weekly rhythm

/// Weekday by hour, darker where more meetings start or more dictations land, and the figures
/// that go with it.
struct RhythmPanel: View {
    let rhythm: TimelineReport.Rhythm
    let weekdays: [Int]
    @Binding var mode: TimelineModel.Mode
    let play: TimelinePlay

    private static let cellHeight: CGFloat = 16
    private static let hourLabels = Dictionary(uniqueKeysWithValues: stride(from: 0, to: 24, by: 3).map {
        ($0, String(format: "%02d", $0))
    })

    private var showsDictation: Bool { mode == .dictation && rhythm.dictation != nil }
    private var grid: TimelineReport.RhythmGrid { showsDictation ? rhythm.dictation ?? rhythm.meetings : rhythm.meetings }
    private var noun: (one: String, many: String) { showsDictation ? ("dictation", "dictations") : ("meeting", "meetings") }

    var body: some View {
        TimelinePanel("Weekly rhythm", play: play) {
            Spacer()
            if rhythm.dictation != nil {
                SegmentedPill(selection: $mode, options: [(.meetings, "Meetings"), (.dictation, "Dictation")])
            }
        } content: {
            HeatGrid(
                columns: (0..<24).map { hour in grid.levels.map { $0[hour] } },
                rowLabels: weekdays.map(TimelineText.weekday),
                columnLabels: Self.hourLabels,
                cellHeight: Self.cellHeight,
                label: headline,
                values: zip(weekdays, grid.counts).map { weekday, hours in
                    "\(TimelineText.weekdayName(weekday)): \(TimelineText.count(hours.reduce(0, +), noun.one, noun.many))"
                }
            )
            FlowLayout(spacing: DS.Space.s10) {
                if let busiest = grid.busiest {
                    StatFigure(
                        text: "\(TimelineText.weekday(busiest.weekday)) \(TimelineText.clock(Double(busiest.hour * 3_600)))",
                        label: "Busiest hour"
                    )
                }
                StatFigure(Double(rhythm.backToBack), format: { StatFormat.pageNumber($0) }, label: "Back-to-back meetings")
                if let start = rhythm.earliestStart, let finish = rhythm.latestFinish {
                    StatFigure(
                        text: "\(TimelineText.clock(start)) – \(TimelineText.clock(finish))",
                        label: "Earliest start, latest finish",
                        spoken: "Earliest start \(TimelineText.clock(start)), latest finish \(TimelineText.clock(finish))"
                    )
                }
            }
        }
    }

    private var headline: String {
        let what = showsDictation ? "Dictations by weekday and hour" : "Meeting starts by weekday and hour"
        guard let busiest = grid.busiest else { return what }
        return "\(what), most on \(TimelineText.weekdayName(busiest.weekday)) at "
            + TimelineText.clock(Double(busiest.hour * 3_600))
    }
}

// MARK: - 4 Talk share

/// The user's share of speech, pace and questions over meetings where their voice is told apart.
struct TalkSharePanel: View {
    let talk: TimelineReport.TalkShare
    let play: TimelinePlay

    private static func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        TimelinePanel("Talk share", play: play) {
            SplitBar(
                share: talk.share, title: "You", rest: "Everyone else",
                label: "You \(Self.percent(talk.share)), everyone else \(Self.percent(1 - talk.share))"
            )
            HStack(alignment: .top, spacing: DS.Space.s10) {
                FlowLayout(spacing: DS.Space.s10) {
                    StatFigure(
                        talk.wordsPerMinute.rounded(), format: { StatFormat.pageNumber($0) }, label: "Your words a minute"
                    )
                    StatFigure(Double(talk.questions), format: { StatFormat.pageNumber($0) }, label: "Questions you asked")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    BarChart(
                        bars: talk.recent.map { BarChart.Bar(parts: [$0], spoken: Self.percent($0)) },
                        colors: [DS.Colors.accent],
                        height: 44,
                        maximum: 1,
                        spacing: DS.Space.s1,
                        label: "Your share in each of the last \(talk.recent.count) meetings"
                    )
                    Text("Your share in the last \(TimelineText.count(talk.recent.count, "meeting", "meetings"))")
                        .textStyle(.meta)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(
                "Counts \(TimelineText.count(talk.meetings, "meeting", "meetings")) where your voice is told apart:"
                    + " every remote call, and in-room meetings with a speaker marked as you."
            )
            .textStyle(.meta)
            .foregroundStyle(DS.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
