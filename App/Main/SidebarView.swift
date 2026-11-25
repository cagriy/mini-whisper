import AppKit
import MWStats
import SwiftUI

/// The sidebar (design §5.8, §5.9, R2, R3, R5): search, Start Meeting or the recording pill, the
/// destinations with Settings' sections while Settings shows, the stats block and the usage table,
/// with the window's shortcuts.
struct SidebarView: View {
    @Bindable var model: MainWindowModel

    @FocusState private var searchFocused: Bool

    private var destination: MainNavigationModel.Destination { model.navigation.destination }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            SearchPill(text: $model.query, focused: $searchFocused, hint: "⌘F")
            Group {
                if let live = model.liveMeeting {
                    RecordingPill(model: live, action: model.showLiveMeeting)
                } else {
                    Button(action: model.startMeeting) {
                        Label("Start Meeting", systemImage: "waveform").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.primary))
                }
            }
            .keyboardShortcut("n")
            VStack(spacing: DS.Space.s1) {
                NavRow(title: "Meetings", symbol: "waveform", selected: destination == .meetings) {
                    model.navigation.go(.meetings)
                }
                .keyboardShortcut("1")
                NavRow(title: "Dictations", symbol: "mic", selected: destination == .dictations) {
                    model.navigation.go(.dictations)
                }
                .keyboardShortcut("2")
                NavRow(title: "Timeline", symbol: "chart.bar", selected: destination == .timeline) {
                    model.navigation.go(.timeline)
                }
                .keyboardShortcut("3")
                NavRow(
                    title: "Settings", symbol: "slider.horizontal.3", chevron: true, selected: destination == .settings
                ) {
                    model.navigation.go(.settings)
                }
                .keyboardShortcut(",")
                if destination == .settings {
                    sections
                }
            }
            .padding(.top, DS.Space.s2)
            foot
                // The gap a spacer above it would add.
                .padding(.top, DS.Space.s5)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        // The traffic lights sit above the search pill.
        .padding(EdgeInsets(top: DS.Space.s7 + 34, leading: DS.Space.s6, bottom: DS.Space.s6, trailing: DS.Space.s6))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.Colors.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DS.Colors.line).frame(width: DS.Size.hairline)
        }
        .background { shortcuts }
    }

    /// The usage table under the stats block as it fits (design §5 Interfaces › Sidebar, R25): whole,
    /// without its trend, or not at all, the handle going with it. Each candidate carries the table, so
    /// `ViewThatFits` is the stack's one flexible child and is offered all the room the rows leave: in a
    /// stack beside the table it would be offered only a share.
    @ViewBuilder private var foot: some View {
        if let stats = model.sidebarStats, model.showsStats, !model.statsFolded {
            ViewThatFits(in: .vertical) {
                blockOverTable(stats, trend: true)
                blockOverTable(stats, trend: false)
                UsageTableView(table: model.usageTable)
            }
        } else {
            UsageTableView(table: model.usageTable, handle: model.showsStats ? foldHandle : nil)
        }
    }

    private func blockOverTable(_ stats: SidebarStats, trend: Bool) -> some View {
        VStack(spacing: DS.Space.s5) {
            StatsBlockView(stats: stats, showsTrend: trend, open: model.openTimeline)
            UsageTableView(table: model.usageTable, handle: foldHandle)
        }
    }

    private var foldHandle: StatsFoldHandle {
        StatsFoldHandle(folded: model.statsFolded, toggle: model.toggleStatsFold)
    }

    private var sections: some View {
        VStack(spacing: DS.Size.hairline) {
            ForEach(SettingsModel.Section.allCases) { section in
                SectionRow(title: section.title, selected: model.settings.selection == section) {
                    model.settings.selection = section
                }
            }
        }
        .padding(EdgeInsets(top: DS.Space.s1, leading: DS.Space.s9, bottom: DS.Space.s1, trailing: 0))
    }

    /// ⌘F and ⌘W have no control of their own to sit on.
    private var shortcuts: some View {
        ZStack {
            Button("Search") { searchFocused = true }
                .keyboardShortcut("f")
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// A destination: symbol and title, filled when it is the page shown or hovered.
private struct NavRow: View {
    let title: String
    let symbol: String
    var chevron = false
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s4) {
                Image(systemName: symbol)
                    .font(DS.TextStyle.body.font)
                    .frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(DS.TextStyle.label.font)
                        // Turned down while the sections show beneath it.
                        .rotationEffect(.degrees(selected ? 90 : 0))
                        .animation(.easeOut(duration: 0.15), value: selected)
                }
            }
            .textStyle(DS.TextStyle.body.weight(.medium))
            .foregroundStyle(selected ? DS.Colors.text : DS.Colors.textSecondary)
            .padding(.horizontal, DS.Space.s4)
            .frame(height: DS.Size.control)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.field)
                    .fill(selected || hovered ? DS.Colors.hover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.field))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One of Settings' sections, as text beneath Settings.
private struct SectionRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(selected ? DS.TextStyle.body.weight(.semibold) : .body)
                .foregroundStyle(selected ? DS.Colors.text : DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.small)
                        .fill(selected || hovered ? DS.Colors.hover : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.small))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
