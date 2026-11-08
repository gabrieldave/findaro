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
                TextField("Ruta o ~/carpeta", text: $browser.pathOmniboxDraft)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced))
                    .focused($omniboxFocused)
                    .onSubmit { browser.submitPathOmnibox() }
                    .onExitCommand { browser.cancelPathOmnibox() }
                    .frame(minWidth: 220, maxWidth: 480)
                Button("Ir") { browser.submitPathOmnibox() }
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
                .help("Editar ruta · ⌘E (Enter confirma) · o ⌘3 diálogo")
            }

            if browser.flattenFolderView {
                FindaroStatusPill(title: "plana", kind: .warning)
                    .help("Vista plana activa")
            }
            if browser.showHiddenFiles {
                FindaroStatusPill(title: "ocultos", kind: .processing)
                    .help("Mostrando archivos ocultos")
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
