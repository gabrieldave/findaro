import SwiftUI
import OrdenCore

/// Omnibox: breadcrumbs clicables o campo de ruta editable (⌘E / clic en lápiz).
struct PathBreadcrumbBar: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var omniboxFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if browser.pathOmniboxEditing {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OrdenTheme.accent)
                TextField(L10n.s("Ruta o ~/carpeta", "Path or ~/folder"), text: $browser.pathOmniboxDraft)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced))
                    .focused($omniboxFocused)
                    .onSubmit { browser.submitPathOmnibox() }
                    .onExitCommand { browser.cancelPathOmnibox() }
                    .frame(minWidth: 220, maxWidth: 480)
                Button(L10n.s("Ir", "Go")) { browser.submitPathOmnibox() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(OrdenTheme.accent)
                    .keyboardShortcut(.defaultAction)
                Button("Esc") { browser.cancelPathOmnibox() }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .keyboardShortcut(.cancelAction)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(browser.pathSegments.enumerated()), id: \.offset) { index, segment in
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
                            .foregroundStyle(index == browser.pathSegments.count - 1 ? .primary : OrdenTheme.textSecondary)
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
                .help(L10n.s("Editar ruta · ⌘E (Enter confirma) · o ⌘3 diálogo", "Edit path · ⌘E (Enter confirms) · or ⌘3 dialog"))
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
                    omniboxFocused || browser.pathOmniboxEditing
                        ? OrdenTheme.accent.opacity(0.55)
                        : OrdenTheme.hairline,
                    lineWidth: 1
                )
        )
        .onChange(of: browser.pathOmniboxEditing) { _, editing in
            if editing {
                DispatchQueue.main.async { omniboxFocused = true }
            }
        }
    }
}
