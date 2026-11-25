import Foundation
import MWStats
import SwiftUI

// MARK: - 5 Spend

/// Twelve months of estimated spend stacked by purpose, with this year, all time and per hour.
struct SpendPanel: View {
    let spend: TimelineReport.Spending
    let play: TimelinePlay

    private static let height: CGFloat = 132
    private static let purposes = TimelineReport.Purpose.allCases

    private static func name(_ purpose: TimelineReport.Purpose) -> String {
        switch purpose {
        case .dictation: "Dictation"
        case .meeting: "Meetings"
        case .summary: "Summaries"
        case .naming: "Naming"
        case .unsplit: "Not split"
        }
    }

    private static func color(_ purpose: TimelineReport.Purpose) -> Color {
        switch purpose {
        case .dictation: ChartColors.dictation
        case .meeting: ChartColors.meetings
        case .summary: ChartColors.summaries
        case .naming: ChartColors.naming
        case .unsplit: ChartColors.unsplit
        }
    }

    var body: some View {
        TimelinePanel("Spend", play: play) {
            Chip("Estimate")
            Spacer()
            ChartLegend(series: spend.series.map { (Self.name($0), Self.color($0)) })
        } content: {
            BarChart(
                bars: spend.months.map { month in
                    let parts = Self.purposes.map { month.amounts[$0] ?? 0 }
                    return BarChart.Bar(
                        parts: parts,
                        axis: TimelineText.monthInitial(month.month),
                        spoken: "\(TimelineText.monthName(month.month)) \(month.year): "
                            + StatFormat.money(parts.reduce(0, +))
                    )
                },
                colors: Self.purposes.map(Self.color),
                height: Self.height,
                label: "Estimated spend by month, "
                    + "\(StatFormat.money(spend.months.reduce(0) { $0 + $1.amounts.values.reduce(0, +) })) in 12 months"
            )
            FlowLayout(spacing: DS.Space.s10) {
                StatFigure(spend.thisYear, format: StatFormat.money, label: "\(String(thisYear)) so far")
                StatFigure(spend.allTime, format: StatFormat.money, label: "All time")
                if let hourly = spend.perRecordedHour {
                    StatFigure(hourly, format: StatFormat.money, label: "Per recorded hour")
                }
            }
            if spend.showsUnsplitCaption {
                Text(
                    "This month's usage was recorded before costs were split by purpose, so it shows as one part."
                        + " Earlier months come from the meetings still stored."
                )
                .textStyle(.meta)
                .foregroundStyle(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var thisYear: Int { spend.months.last?.year ?? 0 }
}

// MARK: - 7 Dictation

/// Words dictated, time saved, pace, the apps dictated into, and the typical and longest dictation.
struct DictationPanel: View {
    let dictation: TimelineReport.Dictation
    /// By bundle identifier.
    let appNames: [String: String]
    let changeTypingSpeed: () -> Void
    let play: TimelinePlay

    private static let nameWidth: CGFloat = 78
    private static let rowHeight: CGFloat = 26

    private var number: (Double) -> String { { StatFormat.pageNumber($0) } }

    var body: some View {
        TimelinePanel("Dictation", play: play) {
            FlowLayout(spacing: DS.Space.s10) {
                StatFigure(Double(dictation.words), format: number, label: "Words dictated")
                StatFigure(
                    dictation.savedTyping, format: { StatFormat.duration($0) },
                    label: "Saved against typing at \(dictation.typingWPM) words a minute"
                ) {
                    Button("Change…", action: changeTypingSpeed)
                        .buttonStyle(.pill(.quietAction, size: .small))
                        // Drawn at full size but laid out as one line of the label, so it moves nothing.
                        .padding(.vertical, (DS.TextStyle.meta.lineHeight - DS.Size.controlSmall) / 2)
                }
                if let pace = dictation.wordsPerMinute {
                    StatFigure(pace.rounded(), format: number, label: "Words a minute while dictating")
                }
            }
            HStack(alignment: .top, spacing: DS.Space.s10) {
                if !dictation.apps.isEmpty {
                    apps.frame(maxWidth: .infinity, alignment: .leading)
                }
                FlowLayout(spacing: DS.Space.s10) {
                    if let typical = dictation.typical {
                        StatFigure(typical.rounded(), format: number, label: "Words in a typical dictation")
                    }
                    if let longest = dictation.longest {
                        StatFigure(Double(longest), format: number, label: "Words in the longest")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var apps: some View {
        let most = Double(dictation.apps.first?.count ?? 1)
        return Grid(alignment: .leading, horizontalSpacing: DS.Space.s5, verticalSpacing: 0) {
            ForEach(dictation.apps.indices, id: \.self) { index in
                let app = dictation.apps[index]
                let title = name(of: app)
                GridRow {
                    Tile(glyph: AppGlyph(appName: title, bundleID: app.bundleID), small: true)
                        .frame(minHeight: Self.rowHeight)
                    Text(title)
                        .textStyle(DS.TextStyle.body.weight(.medium))
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(1)
                        .frame(width: Self.nameWidth, alignment: .leading)
                    MeterBar(fraction: Double(app.count) / most, index: index, height: 8)
                    Text(StatFormat.pageNumber(app.count))
                        .textStyle(.meta)
                        .monospacedDigit()
                        .foregroundStyle(DS.Colors.textSecondary)
                        .gridColumnAlignment(.trailing)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apps dictated into, most into \(name(of: dictation.apps[0]))")
        .accessibilityChildren {
            ForEach(dictation.apps.indices, id: \.self) { index in
                let app = dictation.apps[index]
                Text("\(name(of: app)): \(TimelineText.count(app.count, "dictation", "dictations"))")
            }
        }
    }

    private func name(of app: TimelineReport.App) -> String {
        appNames[app.bundleID] ?? app.bundleID
    }
}

// MARK: - 8 Records

/// The longest, busiest and most of everything, then how far the next milestones are. A record of a
/// kept meeting opens it; one of a deleted meeting says so and is not a control.
struct RecordsPanel: View {
    let records: TimelineReport.Records
    let open: (TimelineReport.MeetingRecord) -> Void
    let play: TimelinePlay

    private struct Line {
        let key: String
        let value: String
        let detail: String
        var record: TimelineReport.MeetingRecord?
    }

    private var lines: [Line] {
        var lines: [Line] = []
        if let longest = records.longestMeeting {
            lines.append(meetingLine("Longest meeting", StatFormat.duration(longest.amount), longest))
        }
        if let busiest = records.busiestDay {
            let meetings = TimelineText.count(busiest.meetings, "meeting", "meetings")
            lines.append(Line(
                key: "Busiest day", value: "\(meetings), \(StatFormat.duration(busiest.recorded))",
                detail: TimelineText.day(busiest.day, "EEEE d MMM yyyy")
            ))
        }
        if let words = records.mostWords {
            lines.append(Line(
                key: "Most words in a day", value: TimelineText.count(words.words, "word", "words"),
                detail: TimelineText.day(words.day, "EEEE d MMM yyyy")
            ))
        }
        if let streak = records.longestStreak {
            lines.append(Line(
                key: "Longest streak", value: TimelineText.count(streak.days, "day", "days"),
                detail: TimelineText.span(streak.first, streak.last)
            ))
        }
        if let speakers = records.mostSpeakers {
            lines.append(meetingLine(
                "Most speakers", TimelineText.count(Int(speakers.amount), "speaker", "speakers"), speakers
            ))
        }
        return lines
    }

    private func meetingLine(_ key: String, _ value: String, _ record: TimelineReport.MeetingRecord) -> Line {
        let day = TimelineText.day(record.day)
        let detail = record.meeting.map { "\($0.title) · \(day)" } ?? "\(RecordRow.deleted) · \(day)"
        return Line(key: key, value: value, detail: detail, record: record)
    }

    var body: some View {
        let lines = lines
        TimelinePanel("Records", play: play) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ForEach(lines.indices, id: \.self) { index in
                    let line = lines[index]
                    let kept = line.record?.meeting != nil
                    RecordRow(
                        key: line.key, value: line.value, detail: line.detail, deleted: line.record != nil && !kept,
                        open: kept ? { line.record.map(open) } : nil
                    )
                    .timelineFade(index * 4)
                }
            }
            .padding(.horizontal, -DS.Space.s6)
            if !records.next.isEmpty {
                HStack(alignment: .top, spacing: DS.Space.s8) {
                    ForEach(records.next.indices, id: \.self) { index in
                        meter(records.next[index], index: index)
                    }
                }
            }
        }
    }

    private func meter(_ next: NextMilestone, index: Int) -> some View {
        let (one, many) = switch next.ladder {
        case .meetings: ("meeting", "meetings")
        case .hours: ("hour", "hours")
        default: ("dictation", "dictations")
        }
        let goal = TimelineText.count(next.step, one, many)
        let progress = "\(StatFormat.pageNumber(Int(next.total.rounded(.down)))) of \(StatFormat.pageNumber(next.step))"
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(goal)
                .textStyle(DS.TextStyle.body.weight(.medium))
                .foregroundStyle(DS.Colors.text)
            MeterBar(fraction: next.fraction, index: index)
            Text(progress)
                .textStyle(.meta)
                .monospacedDigit()
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next milestone \(goal): \(progress)")
    }
}

/// A record: what it is, its value and when, filled on hover when it opens a meeting.
private struct RecordRow: View {
    static let deleted = "Deleted meeting"

    let key: String
    let value: String
    let detail: String
    let deleted: Bool
    let open: (() -> Void)?

    private static let keyWidth: CGFloat = 150

    @State private var hovered = false

    var body: some View {
        if let open {
            Button(action: open) { row }
                .buttonStyle(.plain)
                .onHover { hovered = $0 }
                .help("Opens the meeting")
                .accessibilityLabel("\(key), \(value), \(detail)")
                .accessibilityHint("Opens the meeting")
        } else {
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(key), \(value), \(detail)")
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s6) {
            Text(key)
                .textStyle(.meta)
                .foregroundStyle(DS.Colors.textTertiary)
                .frame(width: Self.keyWidth, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                Text(value)
                    .textStyle(.rowTitle)
                    .foregroundStyle(DS.Colors.text)
                Text(detail)
                    .textStyle(.meta)
                    .italic(deleted)
                    .foregroundStyle(deleted ? DS.Colors.textTertiary : DS.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if open != nil {
                Image(systemName: "chevron.right")
                    .font(DS.TextStyle.meta.font)
                    .foregroundStyle(DS.Colors.textTertiary)
            }
        }
        .padding(.horizontal, DS.Space.s6)
        .padding(.vertical, DS.Space.s4)
        .background {
            if hovered { RoundedRectangle(cornerRadius: DS.Radius.row).fill(DS.Colors.hover) }
        }
        .contentShape(.rect)
    }
}

// MARK: - 10 Milestones

/// The eight latest milestones on a rail, oldest first.
struct MilestonesPanel: View {
    let milestones: [Milestone]
    let play: TimelinePlay

    static func title(_ milestone: Milestone) -> String {
        let step = milestone.value.formatted(.number)
        switch milestone.ladder {
        case .meetings: return milestone.value == 1 ? "First meeting" : "\(step) meetings"
        case .hours: return milestone.value == 1 ? "First hour recorded" : "\(step) hours recorded"
        case .words: return milestone.value == 1_000_000 ? "1 million words" : "\(step) words"
        case .dictations: return milestone.value == 1 ? "First dictation" : "\(step) dictations"
        case .streak: return "\(step)-day streak"
        }
    }

    var body: some View {
        let items = milestones.map { MilestoneStrand.Item(date: TimelineText.day($0.day), title: Self.title($0)) }
        TimelinePanel("Milestones", play: play) {
            MilestoneStrand(
                items: items,
                label: items.last.map { "Milestones reached, the latest \($0.title) on \($0.date)" } ?? "Milestones reached"
            )
        }
    }
}
