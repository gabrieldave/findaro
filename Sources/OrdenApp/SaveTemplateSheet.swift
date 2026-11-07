import SwiftUI

/// Guardar la vista actual (orden + lista/iconos + filtro) como plantilla con nombre.
struct SaveTemplateSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        OrdenDialogShell {
            OrdenDialogHeader(
                systemImage: "rectangle.stack.badge.plus",
                title: "Nueva plantilla",
                subtitle: "Guarda cómo estás viendo los archivos para volver a esa vista cuando quieras."
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                OrdenDialogSection(title: "Nombre") {
                    TextField("Ej. Más pesados", text: $browser.templateNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .onSubmit { browser.confirmSaveViewTemplate() }
                }

                OrdenDialogHintBox(rows: [
                    .init(icon: "checkmark.circle.fill", tint: .green, text: "Incluye el orden actual (pesados, tipo, nombre…)."),
                    .init(icon: "checkmark.circle.fill", tint: .green, text: "También lista/iconos/columnas y el filtro de tipo si hay uno."),
                    .init(icon: "checkmark.circle.fill", tint: .green, text: "Luego eliges la plantilla en el menú Plantillas.")
                ])
            }
            .padding(16)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: nil,
                cancelTitle: "Cancelar",
                actionTitle: "Guardar plantilla",
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
        if browser.cleanupMode || browser.rule == .heaviestFirst { return "Más pesados" }
        if browser.rule == .downloads { return "Estilo Descargas" }
        if browser.rule == .byType { return "Por tipo" }
        if browser.rule == .newestAddedFirst { return "Más nuevos" }
        return "Mi vista"
    }
}
