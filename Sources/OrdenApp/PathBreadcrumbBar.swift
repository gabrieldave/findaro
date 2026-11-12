import SwiftUI
import AppKit
import OrdenCore

@MainActor
private struct OmniboxPathTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onTab: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField(string: text)
        tf.placeholderString = placeholder
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = .monospacedSystemFont(ofSize: 12.5, weight: .medium)
        tf.lineBreakMode = .byTruncatingHead
        tf.delegate = context.coordinator
        context.coordinator.field = tf

        DispatchQueue.main.async {
            guard let win = tf.window else { return }
            win.makeFirstResponder(tf)
            if let editor = tf.currentEditor() {
                let len = (tf.stringValue as NSString).length
                editor.selectedRange = NSRange(location: len, length: 0)
            }
        }
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        nsView.placeholderString = placeholder
        if nsView.stringValue != text {
            nsView.stringValue = text
            if let editor = nsView.currentEditor() {
                let len = (text as NSString).length
                editor.selectedRange = NSRange(location: len, length: 0)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OmniboxPathTextField
        weak var field: NSTextField?

        init(_ parent: OmniboxPathTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            if parent.text != tf.stringValue {
                parent.text = tf.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                let updated = parent.text
                if control.stringValue != updated {
                    control.stringValue = updated
                }
                let end = (updated as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

struct PathBreadcrumbBar: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        HStack(spacing: 8) {
            if browser.pathOmniboxEditing {
                Image(systemName: "terminal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OrdenTheme.accent)

                OmniboxPathTextField(
                    text: $browser.pathOmniboxDraft,
                    placeholder: L10n.s("Ruta o ~/carpeta (Tab autocompleta)", "Path or ~/folder (Tab autocompletes)"),
                    onSubmit: { browser.submitPathOmnibox() },
                    onCancel: { browser.cancelPathOmnibox() },
                    onTab: { _ = browser.autocompletePathOmnibox() }
                )
                .frame(minWidth: 210, maxWidth: 420, minHeight: 20, maxHeight: 20)

                if let topMatch = browser.pathOmniboxSuggestions.first {
                    Button {
                        browser.pathOmniboxDraft = topMatch.path + "/"
                    } label: {
                        Text("⇥ " + topMatch.lastPathComponent)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(OrdenTheme.accent.opacity(0.16), in: Capsule())
                            .foregroundStyle(OrdenTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("Pulsa Tab o haz clic para completar", "Press Tab or click to autocomplete"))
                }

                Button(L10n.s("Ir", "Go")) { browser.submitPathOmnibox() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(OrdenTheme.accent)

                Button("Esc") { browser.cancelPathOmnibox() }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        let segments = browser.activePathSegments
                        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                            if index > 0 {
                                Image(systemName: "chevron.forward")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(OrdenTheme.textMuted)
                            }
                            Button {
                                browser.navigate(to: segment.path)
                            } label: {
                                Text(segment.title)
                                    .font(.system(.callout))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(index == segments.count - 1 ? .primary : OrdenTheme.textSecondary)
                            .help(segment.path)
                        }
                    }
                }
                .frame(maxWidth: 360)
                .onTapGesture(count: 2) {
                    browser.beginPathOmnibox()
                }

                Button {
                    browser.beginPathOmnibox()
                } label: {
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OrdenTheme.accent)
                }
                .buttonStyle(.borderless)
                .help(L10n.s("Barra de ruta editable · ⌘L (Tab autocompleta, Enter confirma)", "Editable path bar · ⌘L (Tab autocompletes, Enter confirms)"))
            }

            if browser.isExternalOrNetworkActiveVolume && !browser.pathOmniboxEditing {
                Button {
                    browser.cleanMacOSJunkInActiveFolder()
                } label: {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OrdenTheme.warning)
                }
                .buttonStyle(.borderless)
                .help(L10n.s("Unidad externa/red: limpiar basura .DS_Store y ._", "External/network drive: clean .DS_Store & ._ junk"))
            }

            if browser.flattenFolderView {
                FindaroStatusPill(title: L10n.s("plana", "flat"), kind: .warning)
                    .help(L10n.s("Vista plana activa", "Flat view active"))
            }
            if browser.showHiddenFiles {
                FindaroStatusPill(title: L10n.s("ocultos", "hidden"), kind: .processing)
                    .help(L10n.s("Mostrando archivos ocultos", "Showing hidden files"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(OrdenTheme.elevatedFill.opacity(0.72), in: RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous)
                .strokeBorder(
                    browser.pathOmniboxEditing
                        ? OrdenTheme.accent.opacity(0.55)
                        : OrdenTheme.hairline,
                    lineWidth: 1
                )
        )
    }
}
