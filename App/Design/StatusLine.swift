import SwiftUI

/// A line that reports a state, with an optional action at its right.
struct StatusLine<Trailing: View>: View {
    enum Kind {
        /// Work in progress: the bars and a line of text on the accent-soft fill.
        case progress
        /// A note to read before acting, under an info mark.
        case info
        /// Something to put right, in the warning colour across the width on offer.
        case warning
        /// Something that failed, as `warning` but in the recording colour.
        case error
    }

    private let text: String
    private let kind: Kind
    private let trailing: Trailing

    init(_ text: String, _ kind: Kind = .progress, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.kind = kind
        self.trailing = trailing()
    }

    init(_ text: String, _ kind: Kind = .progress) where Trailing == EmptyView {
        self.init(text, kind) { EmptyView() }
    }

    var body: some View {
        HStack(alignment: kind == .info ? .top : .center, spacing: kind == .progress ? DS.Space.s4 : DS.Space.s5) {
            switch kind {
            case .progress:
                PulseBars().foregroundStyle(DS.Colors.accent)
            case .info:
                Image(systemName: "info.circle")
                    .font(DS.TextStyle.body.font)
                    .foregroundStyle(DS.Colors.accent)
                    .padding(.top, 2)
            case .warning, .error:
                EmptyView()
            }
            Text(text)
                .textStyle(.body)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, padding.width)
        .padding(.vertical, padding.height)
        .background(background)
    }

    private var padding: CGSize {
        switch kind {
        case .progress: CGSize(width: DS.Space.s6, height: DS.Space.s4)
        case .info: CGSize(width: DS.Space.s7, height: DS.Space.s6)
        case .warning, .error: CGSize(width: 20, height: DS.Space.s4)
        }
    }

    private var foreground: Color {
        switch kind {
        case .progress, .info: DS.Colors.text
        case .warning: DS.Colors.warn
        case .error: DS.Colors.recording
        }
    }

    @ViewBuilder private var background: some View {
        if kind == .warning || kind == .error {
            DS.Colors.hover
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.row).fill(DS.Colors.accentSoft)
        }
    }
}

/// Four bars in the foreground style. They pulse while `active`, and rest when it is off or
/// Reduce Motion is on.
struct PulseBars: View {
    var active = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period = 1.1
    private static let stagger = 0.15

    var body: some View {
        let moving = active && !reduceMotion
        TimelineView(.animation(paused: !moving)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { bar in
                    Capsule().frame(width: 2, height: moving ? Self.height(of: bar, at: time) : 10)
                }
            }
            .frame(height: 14)
        }
        .accessibilityHidden(true)
    }

    /// Between 4 and 14 points, each bar a little behind the one before it.
    private static func height(of bar: Int, at time: TimeInterval) -> CGFloat {
        let phase = (time - Double(bar) * stagger) / period
        return 9 - 5 * cos(2 * .pi * phase)
    }
}
