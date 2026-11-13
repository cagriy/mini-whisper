import AppKit
import SwiftUI

/// The sidebar (design §5.8, §5.9, R2, R5): search, Start Meeting, the destinations and the
/// usage table, with the window's shortcuts.
struct SidebarView: View {
    @Bindable var model: MainWindowModel

    @FocusState private var searchFocused: Bool

    private var destination: MainNavigationModel.Destination { model.navigation.destination }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            SearchPill(text: $model.query, focused: $searchFocused, hint: "⌘F")
            Button(action: model.startMeeting) {
                Label("Start Meeting", systemImage: "waveform").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.primary))
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
                NavRow(title: "Settings", symbol: "slider.horizontal.3", chevron: true, selected: destination == .settings) {
                    model.openSettings()
                }
            }
            .padding(.top, DS.Space.s2)
            Spacer(minLength: 0)
            UsageTableView(table: model.usageTable)
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
                    Image(systemName: "chevron.right").font(DS.TextStyle.label.font)
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
