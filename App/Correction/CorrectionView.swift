import AppKit
import Foundation
import SwiftUI

/// The correction window of design §5.3, restyled in v6 (`mockup-v6-windows.html`): the source
/// line, the selectable transcript, the draft form, the preview and impact, and the confirmation
/// state after Save. Every rule lives in `CorrectionModel`; this is a projection of it.
struct CorrectionView: View {
    @Bindable var model: CorrectionModel
    let onClose: () -> Void

    static let width: CGFloat = 560

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            if model.saved {
                confirmation
            } else {
                editor
            }
            footer
        }
        .smallWindowBody()
        .frame(width: Self.width)
    }

    // MARK: - Editing state

    private var editor: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            sourceLine
            labelled("Transcript — select the misheard phrase") {
                SelectableText(
                    text: model.source.text,
                    selectAll: model.source.preselectAll,
                    onSelect: { model.select($0) }
                )
                .frame(height: 76)
                .background(box(DS.Colors.card))
            }
            grid
            HStack(spacing: DS.Space.s4) {
                Toggle("Remember this correction", isOn: $model.remember)
                    .toggleStyle(.ds)
                Text("Remember this correction")
                    .textStyle(.body)
                    .foregroundStyle(DS.Colors.text)
            }
            labelled("Preview") {
                ScrollView {
                    Text(model.previewText)
                        .textStyle(.body)
                        .foregroundStyle(DS.Colors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 36)
                .padding(.horizontal, DS.Space.s5 + DS.Size.hairline)
                .padding(.vertical, DS.Space.s4 + DS.Size.hairline)
                .background(box())
            }
            impact
        }
    }

    private var sourceLine: some View {
        HStack(spacing: DS.Space.s4) {
            Tile(
                glyph: AppGlyph(appName: model.source.appName ?? "?", bundleID: model.source.bundleID),
                small: true
            )
            Text(sourceText)
                .textStyle(.meta)
                .foregroundStyle(DS.Colors.textSecondary)
        }
    }

    private var sourceText: String {
        var parts = [model.source.appName ?? "Unknown app"]
        if let delivered = model.source.deliveredAt {
            parts.append(Self.timeFormat.string(from: delivered))
        }
        if let engine = model.source.engine, !engine.isEmpty {
            parts.append(HistoryListModel.engineLabel(engine))
        }
        return parts.joined(separator: " · ")
    }

    private var grid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: DS.Space.s7, verticalSpacing: DS.Space.s5) {
            GridRow {
                labelled("Heard") {
                    Text(model.heard.isEmpty ? " " : model.heard)
                        .textStyle(.body)
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Space.s5 + DS.Size.hairline)
                        .frame(height: DS.Size.control)
                        .background(box())
                }
                labelled("Write") {
                    TextField("", text: $model.write).dsField()
                }
            }
            GridRow {
                labelled("Sounds like") {
                    TextField("", text: $model.soundsLike).dsField()
                    help(
                        "Comma-separated spellings the recognizer may produce."
                            + " Sent as hints and matched by the rule."
                    )
                }
                labelled("Scope") {
                    SegmentedPill(
                        selection: $model.scope,
                        options: [(.thisApp, model.thisAppLabel), (.allApps, "All apps")],
                        fillsWidth: true
                    )
                    .disabled(!model.canScopeToApp)
                    help(scopeHelp)
                }
            }
        }
    }

    private var scopeHelp: String {
        guard model.canScopeToApp else {
            return "This dictation’s app has no bundle ID, so the rule can only apply everywhere."
        }
        guard model.scope == .thisApp else {
            return "Replaces exact whole-phrase matches in future dictations in every app."
        }
        return "Replaces exact whole-phrase matches in future dictations to \(model.scopeName)."
    }

    /// Room for the line and three snippets, so the window, sized once, holds whatever arrives.
    private var impact: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = model.validationError {
                ErrorLine(error)
            } else if let line = model.impactLine {
                help(line)
                ForEach(model.impact?.snippets ?? [], id: \.self) { snippet in
                    help("• \(snippet)").lineLimit(1)
                }
            }
        }
        .frame(height: 4 * DS.TextStyle.meta.lineHeight, alignment: .topLeading)
    }

    // MARK: - Confirmation state (R32)

    private var confirmation: some View {
        VStack(spacing: DS.Space.s4) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Colors.canvas)
                .frame(width: 44, height: 44)
                .background(Circle().fill(DS.Colors.ok))
                .accessibilityHidden(true)
            Text(model.confirmationTitle)
                .textStyle(.heading2)
                .foregroundStyle(DS.Colors.text)
            Text(model.confirmationDetail)
                .textStyle(.body)
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DS.Space.s4) {
            Button("Copy corrected text") { Task { await model.copy() } }
                .buttonStyle(.pill(size: .small))
            if let saveError = model.saveError {
                ErrorLine(saveError).lineLimit(2)
            }
            Spacer()
            if model.saved {
                Button("Done", action: onClose)
                    .buttonStyle(.pill(.primary))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", action: onClose)
                    .buttonStyle(.pill())
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { await model.save() } }
                    .buttonStyle(.pill(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
        }
        .padding(.top, DS.Space.s6 + DS.Size.hairline)
        .hairline(.top)
    }

    // MARK: - Pieces

    private func labelled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(title)
                .textStyle(.meta.weight(.medium))
                .foregroundStyle(DS.Colors.textSecondary)
            content()
        }
    }

    private func help(_ text: String) -> some View {
        Text(text)
            .textStyle(.meta)
            .foregroundStyle(DS.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A read-only box: a hairline round the field's shape, filled for the transcript.
    private func box(_ fill: Color = .clear) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.field)
            .fill(fill)
            .strokeBorder(DS.Colors.line)
    }
}

/// A read-only, selectable transcript. SwiftUI's `Text` cannot report a selection, so the
/// window borrows `NSTextView` and forwards `textViewDidChangeSelection` to the model,
/// which owns the snapping rule (§5.3, R29).
private struct SelectableText: NSViewRepresentable {
    let text: String
    let selectAll: Bool
    let onSelect: (NSRange) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = DS.TextStyle.body.nsFont
        textView.textColor = DS.Colors.text.nsColor
        textView.selectedTextAttributes = [.backgroundColor: DS.Colors.accentSoft.nsColor]
        // The box's padding inside its hairline, less the 5 points a line fragment already pads.
        textView.textContainerInset = NSSize(
            width: DS.Space.s5 + DS.Size.hairline - 5, height: DS.Space.s4 + DS.Size.hairline
        )
        textView.string = text
        // R35: a tally phrase is its own transcript, so it arrives already selected.
        // Set before the delegate, so the model hears the user's selections only.
        if selectAll { textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length)) }
        textView.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else {
            return
        }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelect: (NSRange) -> Void

        init(onSelect: @escaping (NSRange) -> Void) {
            self.onSelect = onSelect
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onSelect(textView.selectedRange())
        }
    }
}
