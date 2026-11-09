import SwiftUI
import OrdenCore

/// Ir a carpeta o archivo (⌘3) — mismo chrome formal que la búsqueda.
struct GoToFolderSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        OrdenDialogShell {
            OrdenDialogHeader(
                systemImage: "arrow.right.circle.fill",
                title: L10n.s("Ir a carpeta o archivo", "Go to Folder or File"),
                subtitle: L10n.s("Abre cualquier ruta o archivo de tu Mac", "Open any path or file on your Mac")
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                OrdenDialogSection(title: L10n.s("Ruta", "Path")) {
                    TextField("~/Documents  ·  /Users/…  ·  /Volumes/…", text: $browser.goToFolderDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .focused($fieldFocused)
                        .onSubmit { browser.submitGoToFolder() }
                    Text(L10n.s("Puedes pegar una ruta de carpeta o archivo, o empezar con ~/ para tu carpeta de usuario.", "Paste any folder or file path, or start with ~/ for your home folder."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OrdenDialogHintBox(rows: [
                    .init(icon: "checkmark.circle.fill", tint: .green, text: L10n.s("~/Descargas o ~/Documents funcionan igual que la ruta larga.", "~/Downloads or ~/Documents work the same as the full path.")),
                    .init(icon: "arrow.up.forward.app.fill", tint: OrdenTheme.accent, text: L10n.s("Si introduces un archivo, lo abre de inmediato y va a su carpeta.", "Entering a file opens it immediately and reveals its parent folder.")),
                    .init(icon: "info.circle.fill", tint: .secondary, text: L10n.s("Si la ruta no existe o no hay permiso, Findaro te lo indica abajo.", "If the path does not exist or permission is denied, Findaro alerts you below."))
                ])
            }
            .padding(20)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: L10n.s("Atajo ⌘3", "Shortcut ⌘3"),
                cancelTitle: L10n.s("Cancelar", "Cancel"),
                actionTitle: L10n.s("Ir", "Go"),
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
