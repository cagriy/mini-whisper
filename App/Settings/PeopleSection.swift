import SwiftUI

/// Design v8 §5 UI surfaces, People (mockup `mockup-v8-people.html`): what is kept, then a card of
/// everyone remembered with their actions on hover or focus; or, before anyone, the empty page.
struct PeopleSection: View {
    let model: PeopleModel

    var body: some View {
        if model.rows.isEmpty {
            EmptyPeople(openMeetingsSettings: model.openMeetingsSettings)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                Text(PeopleModel.lead)
                    .textStyle(.body)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = model.recordingLine {
                    StatusLine(line, .info)
                }
                Card(model.groupTitle) {
                    ForEach(model.rows) { PersonRow(model: model, row: $0) }
                }
            }
        }
    }
}

/// A person's name and routes; Rename and Merge into… appear in reserved space on hover or focus.
private struct PersonRow: View {
    let model: PeopleModel
    let row: PeopleModel.Row

    private enum Action: Hashable {
        case rename, merge
    }

    @State private var hovered = false
    @FocusState private var focused: Action?
    @State private var renaming = false
    @State private var draft = ""
    @State private var refusal: String?

    private static let popoverWidth: CGFloat = 220

    private var active: Bool { hovered || focused != nil || renaming }

    var body: some View {
        SettingRow.full {
            HStack(spacing: DS.Space.s6) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DS.Space.s4) {
                        Text(row.name)
                            .textStyle(.rowTitle)
                            .foregroundStyle(DS.Colors.text)
                            .lineLimit(1)
                        if row.isUser { Chip("You") }
                    }
                    if !row.detail.isEmpty {
                        Text(row.detail)
                            .textStyle(.meta)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Kept in the layout when hidden, so hovering never moves the row.
                actions
                    .opacity(active ? 1 : 0)
                    .allowsHitTesting(active)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private var actions: some View {
        HStack(spacing: DS.Space.s1) {
            if row.offersRename {
                Button("Rename") {
                    draft = row.name
                    refusal = nil
                    renaming = true
                }
                .focused($focused, equals: .rename)
                .popover(isPresented: $renaming, arrowEdge: .bottom) { renamePopover }
            }
            if row.offersMerge {
                Button("Merge into…") { PillMenu.popUp(mergeItems) }
                    .focused($focused, equals: .merge)
            }
        }
        .buttonStyle(.pill(.quietAction, size: .small))
        .disabled(!model.canAct)
        .fixedSize()
    }

    /// The menu's first line names what is merged; the person chosen is asked about in a Dialog.
    private var mergeItems: [PillMenu.Item] {
        [PillMenu.Item(title: model.mergeMenuTitle(of: row), enabled: false) {}]
            + model.mergeTargets(for: row).map { target in
                PillMenu.Item(title: model.mergeTitle(of: target)) { model.requestMerge(row, into: target) }
            }
    }

    private var renamePopover: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(model.renameTitle(of: row)).textStyle(.meta).foregroundStyle(DS.Colors.textSecondary)
            TextField("Name", text: $draft)
                .dsField()
                .onSubmit(commitRename)
                .onChange(of: draft) { refusal = nil }
            Group {
                if let refusal {
                    ErrorLine(refusal)
                } else {
                    Text(PeopleModel.renameNote)
                        .textStyle(.meta)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: DS.Space.s4) {
                Spacer(minLength: 0)
                Button("Cancel") { renaming = false }.buttonStyle(.pill(size: .small))
                Button("Rename", action: commitRename)
                    .buttonStyle(.pill(.primary, size: .small))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!PeopleModel.acceptsName(draft))
            }
        }
        .frame(width: Self.popoverWidth, alignment: .leading)
        .padding(DS.Space.s6)
    }

    private func commitRename() {
        guard PeopleModel.acceptsName(draft) else { return }
        Task {
            refusal = await model.rename(row, to: draft)
            if refusal == nil { renaming = false }
        }
    }
}

/// Before anyone is remembered: the mark, how people get here, and the way to the switches.
private struct EmptyPeople: View {
    let openMeetingsSettings: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.s4) {
            Tile.appSoft
            Text(PeopleModel.emptyTitle)
                .textStyle(.title)
                .foregroundStyle(DS.Colors.text)
                .padding(.top, DS.Space.s3)
            Text(PeopleModel.emptyMessage)
                .textStyle(.body)
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
            Button(PeopleModel.openMeetingsTitle, action: openMeetingsSettings)
                .buttonStyle(.pill(size: .small))
                .padding(.top, DS.Space.s3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s10)
    }
}
