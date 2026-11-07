import SwiftUI

/// Ir a carpeta (⌘3) — mismo chrome formal que la búsqueda.
struct GoToFolderSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        OrdenDialogShell {
            OrdenDialogHeader(
                systemImage: "arrow.right.circle.fill",
                title: "Ir a carpeta",
                subtitle: "Abre cualquier ruta de tu Mac"
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                OrdenDialogSection(title: "Ruta") {
                    TextField("~/Documents  ·  /Users/…  ·  /Volumes/…", text: $browser.goToFolderDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .focused($fieldFocused)
                        .onSubmit { browser.submitGoToFolder() }
                    Text("Puedes pegar una ruta completa o empezar con ~/ para tu carpeta de usuario.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OrdenDialogHintBox(rows: [
                    .init(icon: "checkmark.circle.fill", tint: .green, text: "~/Descargas o ~/Documents funcionan igual que la ruta larga."),
                    .init(icon: "info.circle.fill", tint: OrdenTheme.accent, text: "Si la carpeta no existe o no hay permiso, Ordena te lo indica abajo."),
                    .init(icon: "xmark.circle.fill", tint: .secondary, text: "No abre archivos sueltos: solo carpetas.")
                ])
            }
            .padding(20)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: "Atajo ⌘3",
                cancelTitle: "Cancelar",
                actionTitle: "Ir",
                actionDisabled: browser.goToFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onCancel: { browser.showGoToFolderDialog = false },
                onAction: { browser.submitGoToFolder() }
            )
        }
        .onAppear {
            fieldFocused = true
            DispatchQueue.main.async { fieldFocused = true }
        }
    }
}
