import SwiftUI
import OrdenCore

/// Guardar la vista actual (orden + lista/iconos + filtro) como plantilla con nombre.
struct SaveTemplateSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        OrdenDialogShell {
            OrdenDialogHeader(
                systemImage: "rectangle.stack.badge.plus",
                title: L10n.s("Nueva plantilla", "New Template"),
                subtitle: L10n.s("Guarda cómo estás viendo los archivos para volver a esa vista cuando quieras.", "Save current layout and sorting to quickly restore it anytime.")
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                OrdenDialogSection(title: L10n.s("Nombre", "Name")) {
                    TextField(L10n.s("Ej. Más pesados", "e.g. Heaviest files"), text: $browser.templateNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .onSubmit { browser.confirmSaveViewTemplate() }
                }

                OrdenDialogHintBox(rows: [
                    .init(icon: "checkmark.circle.fill", tint: .green, text: L10n.s("Incluye el orden actual (pesados, tipo, nombre…).", "Includes current sorting (heaviest, type, name…).")),
                    .init(icon: "checkmark.circle.fill", tint: .green, text: L10n.s("También lista/iconos/columnas y el filtro de tipo si hay uno.", "Also list/icons/columns and active type filter.")),
                    .init(icon: "checkmark.circle.fill", tint: .green, text: L10n.s("Luego eliges la plantilla en el menú Plantillas.", "Access saved templates anytime from the Templates menu."))
                ])
            }
            .padding(16)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: nil,
                cancelTitle: L10n.s("Cancelar", "Cancel"),
                actionTitle: L10n.s("Guardar plantilla", "Save Template"),
                actionDisabled: browser.templateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onCancel: { browser.showSaveTemplateDialog = false },
                onAction: { browser.confirmSaveViewTemplate() }
            )
        }
        .onAppear {
            if browser.templateNameDraft.isEmpty {
                browser.templateNameDraft = suggestedName
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                fieldFocused = true
            }
        }
    }

    private var suggestedName: String {
        if browser.cleanupMode || browser.rule == .heaviestFirst { return L10n.s("Más pesados", "Heaviest files") }
        if browser.rule == .downloads { return L10n.s("Estilo Descargas", "Downloads style") }
        if browser.rule == .byType { return L10n.s("Por tipo", "By type") }
        if browser.rule == .newestAddedFirst { return L10n.s("Más nuevos", "Newest first") }
        return L10n.s("Mi vista", "My view")
    }
}
