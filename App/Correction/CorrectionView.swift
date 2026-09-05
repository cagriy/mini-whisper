import AppKit
import Foundation
import SwiftUI

/// The correction window of design §5.3, matching the accepted mockup
/// `mockup-v2-correction-window.html`: the source line, the selectable transcript, the
/// draft form, the preview and impact, and the confirmation state after Save.
/// Every rule lives in `CorrectionModel`; this is a projection of it.
struct CorrectionView: View {
    @Bindable var model: CorrectionModel
    let onClose: () -> Void

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.saved {
                confirmation
            } else {
                editor
            }
            Divider()
            footer
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 560, height: 520)
    }

    // MARK: - Editing state

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            sourceLine
            labelled("Transcript — select the misheard phrase") {
                SelectableText(
                    text: model.source.text,
                    selectAll: model.source.preselectAll,
                    onSelect: { model.select($0) }
                )
                .frame(height: 92)
            }
            grid
            Toggle("Remember this correction", isOn: $model.remember)
                .toggleStyle(.switch)
                .controlSize(.small)
            labelled("Preview") {
                ScrollView {
                    Text(model.previewText)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 56)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(box)
            }
            impact
            Spacer(minLength: 0)
        }
    }

    private var sourceLine: some View {
        let glyph = AppGlyph(
            appName: model.source.appName ?? "?", bundleID: model.source.bundleID
        )
        return HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(glyph.color)
                .frame(width: 22, height: 22)
                .overlay(
                    Text(glyph.letters)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                )
            Text(sourceText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                labelled("Heard") {
                    Text(model.heard.isEmpty ? " " : model.heard)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(box.opacity(0.6))
                }
                labelled("Write") {
                    TextField("", text: $model.write)
                        .textFieldStyle(.roundedBorder)
                }
            }
            GridRow {
                labelled("Sounds like") {
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("", text: $model.soundsLike)
                            .textFieldStyle(.roundedBorder)
                        help(
                            "Comma-separated spellings the recognizer may produce."
                                + " Sent as hints and matched by the rule."
                        )
                    }
                }
                labelled("Scope") {
                    VStack(alignment: .leading, spacing: 3) {
                        Picker("Scope", selection: $model.scope) {
                            Text(model.thisAppLabel).tag(CorrectionModel.Scope.thisApp)
                            Text("All apps").tag(CorrectionModel.Scope.allApps)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(!model.canScopeToApp)
                        help(scopeHelp)
                    }
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

    @ViewBuilder
    private var impact: some View {
        if let error = model.validationError {
            Text(error).font(.system(size: 12)).foregroundStyle(.red)
        } else if let line = model.impactLine {
            VStack(alignment: .leading, spacing: 2) {
                Text(line).font(.system(size: 12)).foregroundStyle(.secondary)
                ForEach(model.impact?.snippets ?? [], id: \.self) { snippet in
                    Text("• \(snippet)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Confirmation state (R32)

    private var confirmation: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text(model.confirmationTitle).font(.system(size: 15, weight: .semibold))
            Text(model.confirmationDetail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Copy corrected text") { Task { await model.copy() } }
            if let saveError = model.saveError {
                Text(saveError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            if model.saved {
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Button("Save") { Task { await model.save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
        }
    }

    // MARK: - Pieces

    private func labelled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func help(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var box: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
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
        scroll.borderType = .bezelBorder
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 6, height: 8)
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
