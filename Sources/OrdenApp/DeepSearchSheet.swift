import SwiftUI
import OrdenCore

/// Diálogo formal de búsqueda por nombre (⌘4). No es el asistente/IA.
struct DeepSearchSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        OrdenDialogShell {
            OrdenDialogHeader(
                systemImage: "folder.badge.magnifyingglass",
                title: L10n.s("Buscar en subcarpetas", "Search in Subfolders"),
                subtitle: L10n.s("Desde la carpeta actual hacia abajo", "From active folder and downwards")
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                OrdenDialogSection(title: L10n.s("Ámbito", "Scope")) {
                    Text(OrdenPathDisplay.short(browser.currentPath))
                        .font(.body.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(L10n.s("Incluye esta carpeta y todas las que contiene. No sube a carpetas superiores.", "Includes this folder and all subfolders. Does not search upwards."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OrdenDialogSection(title: L10n.s("Nombre del archivo", "File Name")) {
                    TextField(L10n.s("Ejemplo: vibe · informe · .pdf", "Example: contract · report · .pdf"), text: $browser.deepSearchDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .onSubmit { browser.submitDeepSearchFromDialog() }
                    Text(L10n.s("Coincide con cualquier parte del nombre, incluida la extensión. No distingue mayúsculas.", "Matches any part of the name, including extension. Case insensitive."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OrdenDialogHintBox(rows: [
                    .init(icon: "checkmark.circle.fill", tint: .green, text: L10n.s("Basta con una parte del nombre (vibe encuentra vibesystems…).", "Partial name matches (vibe finds vibesystems…).")),
                    .init(icon: "xmark.circle.fill", tint: .secondary, text: L10n.s("No revisa el contenido dentro de los archivos.", "Does not scan contents inside files.")),
                    .init(icon: "xmark.circle.fill", tint: .secondary, text: L10n.s("No usa comodines (* ?) ni Spotlight.", "Does not use wildcards (* ?) or Spotlight."))
                ])
            }
            .padding(20)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: L10n.s("Atajo ⌘4", "Shortcut ⌘4"),
                cancelTitle: L10n.s("Cancelar", "Cancel"),
                actionTitle: L10n.s("Buscar", "Search"),
                actionDisabled: browser.deepSearchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onCancel: { browser.showDeepSearchDialog = false },
                onAction: { browser.submitDeepSearchFromDialog() }
            )
        }
        .onAppear { focusField() }
    }

    private func focusField() {
        fieldFocused = true
        DispatchQueue.main.async { fieldFocused = true }
    }
}
