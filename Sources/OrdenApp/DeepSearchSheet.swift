import SwiftUI
import OrdenCore

/// Diálogo formal de búsqueda por nombre (⌘4). No es el asistente/IA.
struct DeepSearchSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var fieldFocused: Bool

    private var scopePath: String {
        shortPath(browser.currentPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35)
            content
            Divider().opacity(0.35)
            footer
        }
        .frame(width: 440)
        .background(OrdenTheme.windowFill)
        .onAppear {
            fieldFocused = true
            DispatchQueue.main.async {
                fieldFocused = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder.badge.magnifyingglass")
                .font(.title2)
                .foregroundStyle(OrdenTheme.accent)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 4) {
                Text("Buscar en subcarpetas")
                    .font(.title3.weight(.semibold))
                Text("Desde la carpeta actual hacia abajo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ámbito")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(scopePath)
                    .font(.body.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("Incluye esta carpeta y todas las que contiene. No sube a carpetas superiores.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Nombre del archivo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                TextField("Ejemplo: vibe · informe · .pdf", text: $browser.deepSearchDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { submit() }
                Text("Coincide con cualquier parte del nombre, incluida la extensión. No distingue mayúsculas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                ruleRow(
                    icon: "checkmark.circle.fill",
                    tint: .green,
                    text: "Basta con una parte del nombre (vibe encuentra vibesystems…)."
                )
                ruleRow(
                    icon: "xmark.circle.fill",
                    tint: .secondary,
                    text: "No revisa el contenido dentro de los archivos."
                )
                ruleRow(
                    icon: "xmark.circle.fill",
                    tint: .secondary,
                    text: "No usa comodines (* ?) ni Spotlight."
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Text("Atajo ⌘4")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Cancelar") {
                browser.showDeepSearchDialog = false
            }
            .keyboardShortcut(.cancelAction)
            Button("Buscar") { submit() }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(browser.deepSearchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func ruleRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() {
        browser.submitDeepSearchFromDialog()
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}
