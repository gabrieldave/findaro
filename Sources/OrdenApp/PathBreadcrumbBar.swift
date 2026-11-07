import SwiftUI
import OrdenCore

/// Omnibox: breadcrumbs clicables o campo de ruta editable (⌘L / clic en lápiz).
struct PathBreadcrumbBar: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var omniboxFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if browser.pathOmniboxEditing {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                Button("Esc") { browser.cancelPathOmnibox() }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(browser.pathSegments.enumerated()), id: \.offset) { index, segment in
                            if index > 0 {
                                Image(systemName: "chevron.forward")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            Button {
                                browser.navigate(to: segment.path)
                            } label: {
                                Text(segment.title)
                                    .font(.system(.callout, design: .rounded))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(index == browser.pathSegments.count - 1 ? .primary : .secondary)
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
                }
                .buttonStyle(.borderless)
                .help("Editar ruta / Ir a carpeta… (⌘L o ⌘3)")
            }

            if browser.flattenFolderView {
                Text("plana")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.25), in: Capsule())
                    .help("Vista plana activa")
            }
            if browser.showHiddenFiles {
                Text("ocultos")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.25), in: Capsule())
                    .help("Mostrando archivos ocultos")
            }
        }
        .onChange(of: browser.pathOmniboxEditing) { _, editing in
            if editing {
                DispatchQueue.main.async { omniboxFocused = true }
            }
        }
    }
}
