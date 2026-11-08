import SwiftUI

/// Ir a carpeta o archivo (⌘3) — mismo chrome formal que la búsqueda.
struct GoToFolderSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        OrdenDialogShell {
            OrdenDialogHeader(
                systemImage: "arrow.right.circle.fill",
                title: "Ir a carpeta o archivo",
                subtitle: "Abre cualquier ruta o archivo de tu Mac"
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                OrdenDialogSection(title: "Ruta") {
                    TextField("~/Documents  ·  /Users/…  ·  /Volumes/…", text: $browser.goToFolderDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .focused($fieldFocused)
                        .onSubmit { browser.submitGoToFolder() }
                    Text("Puedes pegar una ruta de carpeta o archivo, o empezar con ~/ para tu carpeta de usuario.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OrdenDialogHintBox(rows: [
                    .init(icon: "checkmark.circle.fill", tint: .green, text: "~/Descargas o ~/Documents funcionan igual que la ruta larga."),
                    .init(icon: "arrow.up.forward.app.fill", tint: OrdenTheme.accent, text: "Si introduces un archivo, lo abre de inmediato y va a su carpeta."),
                    .init(icon: "info.circle.fill", tint: .secondary, text: "Si la ruta no existe o no hay permiso, Findaro te lo indica abajo.")
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
