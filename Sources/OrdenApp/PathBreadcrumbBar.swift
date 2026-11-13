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

/// Barra interactiva de Breadcrumbs por carpetas.
/// Clic en cualquier carpeta padre navega de inmediato a ella.
/// Micro-acciones integradas a la derecha: Copiar ruta (con checkmark) y Editar ruta (⌘L).
struct PathBreadcrumbBar: View {
    @EnvironmentObject private var browser: BrowserModel
    var pane: BrowserModel.PaneFocus = .primary

    @State private var hoveredSegmentID: String?
    @State private var copiedPathFeedback = false

    private var isSecondary: Bool { pane == .secondary }

    private var currentFolderPath: String {
        isSecondary ? browser.secondaryPath : browser.currentPath
    }

    private var currentFolderURL: URL {
        URL(fileURLWithPath: currentFolderPath)
    }

    private var segments: [BreadcrumbSegment] {
        BreadcrumbResolver.segments(for: currentFolderPath)
    }

    private var isEditingOmnibox: Bool {
        browser.pathOmniboxEditing && (browser.focusedPane == pane || !browser.dualPaneEnabled)
    }

    private var isExternalVolume: Bool {
        VolumeHygienePolicy().inspectVolume(at: currentFolderURL).shouldAvoidAuxiliaryMetadata
    }

    var body: some View {
        HStack(spacing: 6) {
            if isEditingOmnibox {
                omniboxEditingView
            } else {
                breadcrumbsScrollView
            }

            Spacer(minLength: 4)

            trailingQuickActions
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(OrdenTheme.elevatedFill.opacity(0.65), in: RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous)
                .strokeBorder(
                    isEditingOmnibox
                        ? OrdenTheme.accent.opacity(0.65)
                        : OrdenTheme.hairline,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Breadcrumbs ScrollView

    private var breadcrumbsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    let segs = segments
                    ForEach(Array(segs.enumerated()), id: \.element.id) { index, segment in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(OrdenTheme.textMuted)
                                .padding(.horizontal, 2)
                        }

                        let isCurrent = index == segs.count - 1

                        Button {
                            if !isCurrent {
                                browser.openFolder(path: segment.path, pane: pane)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                if let icon = segment.iconName {
                                    Image(systemName: icon)
                                        .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                                        .foregroundStyle(isCurrent ? OrdenTheme.accent : OrdenTheme.textSecondary)
                                }
                                Text(segment.title)
                                    .font(.system(size: 11.5, weight: isCurrent ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(
                                !isCurrent && hoveredSegmentID == segment.id
                                    ? OrdenTheme.accent.opacity(0.12)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isCurrent ? .primary : OrdenTheme.textSecondary)
                        .onHover { isHovered in
                            if isHovered && !isCurrent {
                                hoveredSegmentID = segment.id
                            } else if hoveredSegmentID == segment.id {
                                hoveredSegmentID = nil
                            }
                        }
                        .help(segment.path)
                        .id(segment.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: currentFolderPath) { _, _ in
                if let lastID = segments.last?.id {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(lastID, anchor: .trailing)
                    }
                }
            }
            .onAppear {
                if let lastID = segments.last?.id {
                    proxy.scrollTo(lastID, anchor: .trailing)
                }
            }
        }
    }

    // MARK: - Omnibox Editing

    private var omniboxEditingView: some View {
        HStack(spacing: 6) {
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
            .frame(minWidth: 180, maxWidth: 360, minHeight: 20, maxHeight: 20)

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
        }
    }

    // MARK: - Trailing Quick Actions

    private var trailingQuickActions: some View {
        HStack(spacing: 4) {
            if isExternalVolume && !isEditingOmnibox {
                Button {
                    browser.cleanMacOSJunkInActiveFolder()
                } label: {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OrdenTheme.warning)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(L10n.s("Unidad externa/red: limpiar basura .DS_Store y ._", "External/network drive: clean .DS_Store & ._ junk"))
            }

            if !isEditingOmnibox {
                // Micro-botón copiar ruta (con feedback checkmark verde)
                Button {
                    let path = currentFolderPath
                    let text = NSEvent.modifierFlags.contains(.option)
                        ? PathFormatter.shellEscaped(for: [path])
                        : path
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copiedPathFeedback = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        copiedPathFeedback = false
                    }
                } label: {
                    Image(systemName: copiedPathFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(copiedPathFeedback ? Color.green : OrdenTheme.textSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.s("Copiar ruta actual (⌥⌘C)", "Copy current path (⌥⌘C)"))

                // Micro-botón editar ruta (⌘L)
                Button {
                    browser.beginPathOmnibox()
                } label: {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(OrdenTheme.accent)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.s("Editar ruta (⌘L)", "Edit path (⌘L)"))
            }
        }
    }
}
