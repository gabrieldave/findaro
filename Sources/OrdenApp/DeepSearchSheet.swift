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
                title: "Buscar en subcarpetas",
                subtitle: "Desde la carpeta actual hacia abajo"
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                OrdenDialogSection(title: "Ámbito") {
                    Text(OrdenPathDisplay.short(browser.currentPath))
                        .font(.body.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text("Incluye esta carpeta y todas las que contiene. No sube a carpetas superiores.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OrdenDialogSection(title: "Nombre del archivo") {
                    TextField("Ejemplo: vibe · informe · .pdf", text: $browser.deepSearchDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .onSubmit { browser.submitDeepSearchFromDialog() }
                    Text("Coincide con cualquier parte del nombre, incluida la extensión. No distingue mayúsculas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OrdenDialogHintBox(rows: [
                    .init(icon: "checkmark.circle.fill", tint: .green, text: "Basta con una parte del nombre (vibe encuentra vibesystems…)."),
                    .init(icon: "xmark.circle.fill", tint: .secondary, text: "No revisa el contenido dentro de los archivos."),
                    .init(icon: "xmark.circle.fill", tint: .secondary, text: "No usa comodines (* ?) ni Spotlight.")
                ])
            }
            .padding(20)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: "Atajo ⌘4",
                cancelTitle: "Cancelar",
                actionTitle: "Buscar",
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
