import MWStats
import SwiftUI

/// Timeline (design §5 Interfaces, R17–R22): the sub line, the empty state or the progress line, and
/// each panel that has something to show, in page order. A panel plays once a fifth of it has
/// scrolled into view; a return keeps the place it was left at.
struct TimelinePage: View {
    @Bindable var model: TimelineModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tracking = PanelTracking()

    private typealias Panel = TimelineModel.Panel

    private static let space = "timeline"

    var body: some View {
        PageColumn("Timeline", scrollPosition: $model.anchor, coordinateSpace: Self.space) {
            if let state = model.state {
                if state != .empty, let content = model.content {
                    Text(subLine(since: content.since))
                        .textStyle(.body)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .padding(.top, -DS.Space.s5)
                }
                if case .reading(let done, let total) = state {
                    StatusLine("Reading stored meetings… \(done) of \(total)")
                }
                if state == .empty {
                    EmptyTimeline()
                } else if let report = model.report {
                    VStack(alignment: .leading, spacing: DS.Space.s10) {
                        ForEach(Panel.allCases, id: \.self) { panel($0, of: report) }
                    }
                    .scrollTargetLayout()
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            tracking.viewport = CGRect(origin: .zero, size: size)
            play()
        }
        .onPreferenceChange(PanelFrames.self) { frames in
            tracking.frames = frames
            play()
        }
        // A replay draws every panel's start state first; the panels in view then play from it.
        .onChange(of: model.playID) { Task { play() } }
        .onChange(of: reduceMotion, initial: true) { model.playback.reduceMotion = reduceMotion }
    }

    private func subLine(since: String?) -> String {
        let since = since.map { "Tracking since \(TimelineText.day($0))" }
        return ([since] + ["Kept on this Mac", "Costs are estimates"]).compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private func panel(_ panel: Panel, of report: TimelineReport) -> some View {
        let play = model.playback.play(panel)
        switch panel {
        case .totals:
            if let totals = report.totals {
                TotalsPanel(totals: totals, play: play).tracked(panel, in: Self.space)
            }
        case .year:
            if let years = report.year?.years, let first = years.first, let last = years.last,
               let shown = model.shownYear {
                YearPanel(
                    year: shown, years: first.year...last.year,
                    weekdays: report.weekdays,
                    firstDictationYear: years.first { $0.dictationDays > 0 }?.year,
                    mode: $model.yearMode,
                    selectedYear: Binding(get: { shown.year }, set: { model.selectedYear = $0 }),
                    play: play
                )
                .tracked(panel, in: Self.space)
            }
        case .rhythm:
            if let rhythm = report.rhythm {
                RhythmPanel(rhythm: rhythm, weekdays: report.weekdays, mode: $model.rhythmMode, play: play)
                    .tracked(panel, in: Self.space)
            }
        case .talkShare:
            if let talk = report.talkShare {
                TalkSharePanel(talk: talk, play: play).tracked(panel, in: Self.space)
            }
        case .spend:
            if let spend = report.spend {
                SpendPanel(spend: spend, play: play).tracked(panel, in: Self.space)
            }
        case .dictation:
            if let dictation = report.dictation {
                DictationPanel(
                    dictation: dictation, appNames: model.content?.appNames ?? [:],
                    changeTypingSpeed: model.changeTypingSpeed, play: play
                )
                .tracked(panel, in: Self.space)
            }
        case .records:
            if let records = report.records {
                RecordsPanel(records: records, open: { record in Task { await model.open(record) } }, play: play)
                    .tracked(panel, in: Self.space)
            }
        case .milestones:
            if let milestones = report.milestones {
                MilestonesPanel(milestones: milestones, play: play).tracked(panel, in: Self.space)
            }
        }
    }

    /// Plays the panels not yet played that have come far enough into view. Played panels' frames are
    /// ignored, and the model is written only when a panel starts, so scrolling costs no redraw.
    private func play() {
        let waiting = tracking.frames.filter { !model.playback.play($0.key).played }
        guard !waiting.isEmpty, tracking.viewport.height > 0 else { return }
        var playback = model.playback
        if playback.update(waiting, in: tracking.viewport) { model.playback = playback }
    }
}

/// Where the panels and the viewport last were. A reference, so scrolling writes no view state.
@MainActor
private final class PanelTracking {
    var frames: [TimelineModel.Panel: CGRect] = [:]
    var viewport = CGRect.zero
}

/// Each panel's frame in the page's scroll view.
private struct PanelFrames: PreferenceKey {
    static let defaultValue: [TimelineModel.Panel: CGRect] = [:]

    static func reduce(value: inout [TimelineModel.Panel: CGRect], nextValue: () -> [TimelineModel.Panel: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    /// A scroll target that reports its frame in the coordinate space `space`.
    func tracked(_ panel: TimelineModel.Panel, in space: String) -> some View {
        id(panel).background {
            GeometryReader { proxy in
                Color.clear.preference(key: PanelFrames.self, value: [panel: proxy.frame(in: .named(space))])
            }
        }
    }
}

/// Before anything is recorded: the mark, and what will build up here.
private struct EmptyTimeline: View {
    var body: some View {
        VStack(spacing: DS.Space.s5) {
            CloudPulseMark()
                .stroke(DS.Colors.accent, style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                .frame(width: 72, height: 48)
                .accessibilityHidden(true)
            Text("Nothing to show yet")
                .textStyle(.title)
                .foregroundStyle(DS.Colors.text)
            Text(
                "Record a meeting or dictate something. Your totals, records and milestones build up here,"
                    + " and stay on this Mac."
            )
            .textStyle(.body)
            .foregroundStyle(DS.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s10)
    }
}
