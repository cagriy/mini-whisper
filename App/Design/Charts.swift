import AppKit
import SwiftUI

/// The chart series colours, one per purpose a cost is spent on.
enum ChartColors {
    static let dictation = DS.Colors.teal
    static let meetings = DS.Colors.accent
    static let summaries = DS.Colors.speaker1
    static let naming = DS.Colors.speaker3
    static let unsplit = DS.Colors.textTertiary
}

/// A Timeline panel: an SF heading, with anything that `accessory` puts after it, over figures and
/// charts, open on the canvas under a hairline. The charts inside play from `play`. Without its heading
/// a panel also drops its hairline, as the lifetime totals that open the page do.
struct TimelinePanel<Accessory: View, Content: View>: View {
    private let title: String
    private let showsHeading: Bool
    private let play: TimelinePlay
    private let accessory: Accessory
    private let content: Content

    /// Put a `Spacer` in `accessory` to push what follows it to the trailing edge.
    init(
        _ title: String,
        showsHeading: Bool = true,
        play: TimelinePlay = .final,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.showsHeading = showsHeading
        self.play = play
        self.accessory = accessory()
        self.content = content()
    }

    init(
        _ title: String, showsHeading: Bool = true, play: TimelinePlay = .final, @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.init(title, showsHeading: showsHeading, play: play, accessory: { EmptyView() }, content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeading {
                Color.clear.frame(height: DS.Space.s8).hairline(.top)
            }
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                if showsHeading {
                    HStack(spacing: DS.Space.s5) {
                        Text(title)
                            .textStyle(.heading)
                            .foregroundStyle(DS.Colors.text)
                            .accessibilityAddTraits(.isHeader)
                        accessory
                    }
                    .frame(minHeight: DS.Size.controlSmall)
                }
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.timelinePlay, play)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A figure in the display serif over a `meta` label: `score` for lifetime totals, `title` inside panels.
/// VoiceOver reads figure and label as one sentence, "214 meetings", unless `spoken` gives another.
struct StatFigure<Accessory: View>: View {
    private enum Figure {
        case counting(Double, (Double) -> String)
        case fixed(String)
    }

    private let figure: Figure
    private let label: String
    private let spoken: String
    private let style: DS.TextStyle
    private let accessory: Accessory

    /// A number that counts up when its panel plays. `accessory` follows the label, as a "Change…" link does.
    init(
        _ value: Double,
        format: @escaping (Double) -> String,
        label: String,
        spoken: String? = nil,
        style: DS.TextStyle = .title,
        @ViewBuilder accessory: () -> Accessory
    ) {
        figure = .counting(value, format)
        self.label = label
        self.spoken = spoken ?? Self.sentence(format(value), label)
        self.style = style
        self.accessory = accessory()
    }

    /// A figure that is not a count, such as an hour of the week.
    init(
        text: String, label: String, spoken: String? = nil, style: DS.TextStyle = .title,
        @ViewBuilder accessory: () -> Accessory
    ) {
        figure = .fixed(text)
        self.label = label
        self.spoken = spoken ?? Self.sentence(text, label)
        self.style = style
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch figure {
                case .counting(let value, let format): CountUpText(value: value, format: format)
                case .fixed(let text): Text(text)
                }
            }
            .textStyle(style)
            .monospacedDigit()
            .foregroundStyle(DS.Colors.text)
            .accessibilityHidden(true)
            HStack(spacing: DS.Space.s2) {
                Text(label)
                    .textStyle(.meta)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .accessibilityLabel(spoken)
                accessory
            }
        }
    }

    /// "214" and "Meetings" read as "214 meetings".
    private static func sentence(_ figure: String, _ label: String) -> String {
        "\(figure) \(label.prefix(1).lowercased())\(label.dropFirst())"
    }
}

extension StatFigure where Accessory == EmptyView {
    init(
        _ value: Double, format: @escaping (Double) -> String, label: String, spoken: String? = nil,
        style: DS.TextStyle = .title
    ) {
        self.init(value, format: format, label: label, spoken: spoken, style: style) { EmptyView() }
    }

    init(text: String, label: String, spoken: String? = nil, style: DS.TextStyle = .title) {
        self.init(text: text, label: label, spoken: spoken, style: style) { EmptyView() }
    }
}

/// A number that counts up from zero when its panel plays, in whole steps when it is whole. VoiceOver
/// reads the final value.
struct CountUpText: View {
    let value: Double
    let format: (Double) -> String

    @Environment(\.timelinePlay) private var play

    var body: some View {
        Clocked(time: play.played ? 1 : 0) { share in
            let shown = value * share
            Text(format(value == value.rounded() ? shown.rounded() : shown))
        }
        .animation(play.played ? TimelineMotion.count.animation(after: play.delay) : nil, value: play.played)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(format(value))
    }
}

/// Bars on a hairline baseline, each a stack of its series from the bottom up, growing from the
/// baseline when their panel plays. VoiceOver reads `label`, then one sentence per bar.
struct BarChart: View {
    struct Bar {
        /// One value per series, bottom first.
        let parts: [Double]
        /// Under the bar, such as a month's initial; empty for none.
        var axis = ""
        /// What VoiceOver reads for the bar.
        let spoken: String
    }

    let bars: [Bar]
    /// One per series, bottom first.
    let colors: [Color]
    /// From the baseline to the top of the scale.
    let height: CGFloat
    /// The value at the top of the scale; nil puts the tallest bar there.
    var maximum: Double?
    var spacing = DS.Space.s4
    /// The headline sentence.
    let label: String

    @Environment(\.timelinePlay) private var play

    var body: some View {
        let top = maximum ?? bars.map { $0.parts.reduce(0, +) }.max() ?? 0
        VStack(spacing: DS.Space.s2) {
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(bars.indices, id: \.self) { index in
                    column(bars[index], index: index, top: top)
                }
            }
            .frame(height: height, alignment: .bottom)
            .padding(.bottom, DS.Size.hairline)
            .hairline(.bottom)
            if bars.contains(where: { !$0.axis.isEmpty }) {
                HStack(spacing: spacing) {
                    ForEach(bars.indices, id: \.self) { index in
                        Text(bars[index].axis)
                            .textStyle(.usage)
                            .foregroundStyle(DS.Colors.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func column(_ bar: Bar, index: Int, top: Double) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(bar.parts.indices.reversed()), id: \.self) { part in
                if bar.parts[part] > 0, top > 0, !colors.isEmpty {
                    colors[part % colors.count].frame(height: height * bar.parts[part] / top)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DS.Radius.cell, topTrailingRadius: DS.Radius.cell))
        .scaleEffect(x: 1, y: play.played ? 1 : 0, anchor: .bottom)
        .animation(
            play.played ? TimelineMotion.verticalBars.animation(item: index, after: play.delay) : nil,
            value: play.played
        )
        .accessibilityElement()
        .accessibilityLabel(bar.spoken)
    }
}

/// One `radius.field` bar divided between a share in the accent and the rest in `hover`, each named
/// inside it: "You 34%" and "Everyone else". VoiceOver reads `label`.
struct SplitBar: View {
    /// 0 to 1.
    let share: Double
    /// Names the share; its percentage follows.
    let title: String
    /// Names the rest.
    let rest: String
    let label: String

    @Environment(\.timelinePlay) private var play

    var body: some View {
        let shown = play.played ? min(max(share, 0), 1) : 0
        GeometryReader { geometry in
            let width = geometry.size.width * shown
            ZStack(alignment: .leading) {
                DS.Colors.hover
                Text(rest)
                    .textStyle(DS.TextStyle.meta.weight(.medium))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .padding(.horizontal, DS.Space.s5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                shareName.foregroundStyle(DS.Colors.text)
                DS.Colors.accent.frame(width: width)
                // The same name again, in the accent's ink wherever the accent lies under it.
                shareName
                    .foregroundStyle(DS.Colors.accentOn)
                    .mask(alignment: .leading) { Rectangle().frame(width: width) }
            }
        }
        .frame(height: DS.Size.control)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.field))
        .animation(play.played ? TimelineMotion.horizontalBars.animation(after: play.delay) : nil, value: play.played)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var shareName: some View {
        HStack(spacing: DS.Space.s2) {
            Text(title)
            CountUpText(value: share) { $0.formatted(.percent.precision(.fractionLength(0))) }
        }
        .textStyle(DS.TextStyle.meta.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, DS.Space.s5)
    }
}

/// A thin pill in `hover`, filled to a fraction in the accent from the leading edge when its panel
/// plays: a person's or an app's bar, or a milestone meter. The row around it carries the numbers.
struct MeterBar: View {
    /// 0 to 1.
    let fraction: Double
    /// Its place in a list, for the stagger.
    var index = 0
    /// 6 for a milestone meter; a person's or an app's row passes 8.
    var height: CGFloat = 6

    @Environment(\.timelinePlay) private var play

    var body: some View {
        Capsule()
            .fill(DS.Colors.hover)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(DS.Colors.accent)
                        .frame(width: geometry.size.width * (play.played ? min(max(fraction, 0), 1) : 0))
                }
            }
            .frame(height: height)
            .animation(
                play.played ? TimelineMotion.horizontalBars.animation(item: index, after: play.delay) : nil,
                value: play.played
            )
            .accessibilityHidden(true)
    }
}

/// Heat cells in five steps from `hover` to the accent, drawn as one `Canvas`, with labels down the
/// leading edge and over the columns. Square cells shrink to fit the width, so 54 columns always fit;
/// a `cellHeight` stretches the cells across the width instead. Columns fade in from the leading edge
/// when their panel plays. VoiceOver reads `label`, then one sentence for each of `values`.
struct HeatGrid: View {
    /// Levels 0 to 4, column by column and each column top to bottom; nil leaves the cell out.
    let columns: [[Int?]]
    /// One per row; an empty string leaves the row unlabelled.
    let rowLabels: [String]
    /// Labels over the columns they start at, by column index.
    var columnLabels: [Int: String] = [:]
    /// Cells this tall stretched across the width; nil draws square cells.
    var cellHeight: CGFloat?
    /// The headline sentence.
    let label: String
    /// One per child element: a week with any activity, or a weekday.
    let values: [String]

    /// The widest a square cell gets.
    nonisolated static let squareSide: CGFloat = 10

    private static let labelStyle = DS.TextStyle.usage

    @Environment(\.timelinePlay) private var play

    var body: some View {
        let metrics = Metrics(
            rows: columns.map(\.count).max() ?? 0,
            columns: columns.count,
            gutter: gutter,
            top: columnLabels.isEmpty ? 0 : Self.labelStyle.lineHeight,
            cellHeight: cellHeight
        )
        let length = TimelineMotion.fade.length(items: columns.count)
        Sizing(metrics: metrics) {
            Clocked(time: play.played ? length : 0) { time in
                Canvas { context, size in
                    draw(in: context, width: size.width, at: time, metrics)
                }
            }
            .animation(play.played ? .linear(duration: length).delay(play.delay) : nil, value: play.played)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityChildren {
            ForEach(values.indices, id: \.self) { Text(values[$0]) }
        }
    }

    /// The leading space the row labels take, their widest and `space.3`.
    private var gutter: CGFloat {
        let font = Self.labelStyle.nsFont
        let widest = rowLabels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return widest > 0 ? (widest + DS.Space.s3).rounded(.up) : 0
    }

    private func draw(in context: GraphicsContext, width: CGFloat, at time: TimeInterval, _ metrics: Metrics) {
        let cell = metrics.cell(forWidth: width)
        for (row, text) in rowLabels.prefix(metrics.rows).enumerated() where !text.isEmpty {
            let y = metrics.top + CGFloat(row) * (cell.height + Metrics.gap) + cell.height / 2
            context.draw(labelText(text), at: CGPoint(x: 0, y: y), anchor: .leading)
        }
        for (column, text) in columnLabels where column < metrics.columns {
            let x = metrics.gutter + CGFloat(column) * (cell.width + Metrics.gap)
            context.draw(labelText(text), at: CGPoint(x: x, y: metrics.top / 2), anchor: .leading)
        }
        for (column, levels) in columns.enumerated() {
            let shown = TimelineMotion.fade.progress(at: time, item: column)
            guard shown > 0 else { continue }
            var layer = context
            layer.opacity = shown
            let lift = DS.Space.s2 * (1 - shown)
            for (row, level) in levels.enumerated() {
                guard let level else { continue }
                let origin = CGPoint(
                    x: metrics.gutter + CGFloat(column) * (cell.width + Metrics.gap),
                    y: metrics.top + CGFloat(row) * (cell.height + Metrics.gap) + lift
                )
                let path = Path(roundedRect: CGRect(origin: origin, size: cell), cornerRadius: DS.Radius.cell)
                layer.fill(path, with: .color(DS.Colors.heat(level)))
            }
        }
    }

    private func labelText(_ text: String) -> Text {
        Text(text).font(Self.labelStyle.font).foregroundStyle(DS.Colors.textTertiary)
    }

    /// Where the cells go for a given width.
    private struct Metrics {
        static let gap = DS.Space.s1

        let rows: Int
        let columns: Int
        let gutter: CGFloat
        let top: CGFloat
        let cellHeight: CGFloat?

        func cell(forWidth width: CGFloat) -> CGSize {
            let across = CGFloat(max(columns, 1))
            let fit = max(0, (width - gutter - Self.gap * (across - 1)) / across)
            guard let cellHeight else {
                let side = min(HeatGrid.squareSide, fit)
                return CGSize(width: side, height: side)
            }
            return CGSize(width: fit, height: cellHeight)
        }

        func height(forWidth width: CGFloat) -> CGFloat {
            guard rows > 0 else { return top }
            return top + CGFloat(rows) * cell(forWidth: width).height + Self.gap * CGFloat(rows - 1)
        }

        var idealWidth: CGFloat {
            gutter + CGFloat(columns) * (HeatGrid.squareSide + Self.gap) - Self.gap
        }
    }

    /// Takes the width on offer and the height the cells need at that width.
    private struct Sizing: Layout {
        let metrics: Metrics

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let offered = proposal.width ?? .infinity
            let width = offered.isFinite ? offered : metrics.idealWidth
            return CGSize(width: width, height: metrics.height(forWidth: width))
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            for subview in subviews {
                subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
            }
        }
    }
}

/// A chart's key in the `usage` style: a dot and a name per series, or the five heat steps between
/// "Less" and "More".
struct ChartLegend: View {
    private enum Key {
        case series([(name: String, color: Color)])
        case heat(less: String, more: String)
    }

    private let key: Key

    init(series: [(name: String, color: Color)]) {
        key = .series(series)
    }

    init(less: String, more: String) {
        key = .heat(less: less, more: more)
    }

    var body: some View {
        Group {
            switch key {
            case .series(let series):
                HStack(spacing: DS.Space.s5) {
                    ForEach(series.indices, id: \.self) { index in
                        HStack(spacing: DS.Space.s3) {
                            Circle().fill(series[index].color).frame(width: Self.dot, height: Self.dot)
                            Text(series[index].name)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            case .heat(let less, let more):
                HStack(spacing: DS.Space.s3) {
                    Text(less)
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: DS.Radius.cell)
                            .fill(DS.Colors.heat(level))
                            .frame(width: HeatGrid.squareSide, height: HeatGrid.squareSide)
                    }
                    Text(more)
                }
                .accessibilityHidden(true)
            }
        }
        .textStyle(.usage)
        .foregroundStyle(DS.Colors.textTertiary)
        .fixedSize()
    }

    private static let dot: CGFloat = 8
}

extension View {
    /// Fades in and rises `space.2` into place when its panel plays, `index` items after the first.
    func timelineFade(_ index: Int) -> some View {
        modifier(TimelineFade(index: index))
    }
}

private struct TimelineFade: ViewModifier {
    let index: Int

    @Environment(\.timelinePlay) private var play

    func body(content: Content) -> some View {
        content
            .opacity(play.played ? 1 : 0)
            .offset(y: play.played ? 0 : DS.Space.s2)
            .animation(play.played ? TimelineMotion.fade.animation(item: index, after: play.delay) : nil, value: play.played)
    }
}

/// Draws its content at each step of an animation of `time`, for what an animated value alone cannot
/// move: a number's text, or cells drawn into one `Canvas`.
private struct Clocked<Content: View>: View, Animatable {
    var time: Double
    let content: (Double) -> Content

    init(time: Double, @ViewBuilder content: @escaping (Double) -> Content) {
        self.time = time
        self.content = content
    }

    nonisolated var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    var body: some View {
        content(time)
    }
}
