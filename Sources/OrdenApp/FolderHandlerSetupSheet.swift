import SwiftUI
import OrdenCore

/// Explica el límite de macOS y los pasos reales para abrir carpetas con Findaro.
struct FolderHandlerSetupSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    let result: FolderHandlerSetupResult

    var body: some View {
        OrdenDialogShell {
            OrdenDialogHeader(
                systemImage: "folder.badge.gearshape",
                title: title,
                subtitle: subtitle
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                statusCard

                OrdenDialogSection(title: L10n.s("Cómo dejarlo fijo", "How to set as default")) {
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, L10n.s("Clic derecho en cualquier carpeta", "Right-click any folder"))
                        step(2, L10n.s("Abrir con → Findaro", "Open With → Findaro"))
                        step(3, L10n.s("Vuelve a clic derecho → Abrir con → Siempre", "Right-click again → Open With → Always"))
                    }
                }

                OrdenDialogHintBox(rows: [
                    .init(
                        icon: "checkmark.circle.fill",
                        tint: .green,
                        text: L10n.s("Después, al hacer doble clic en una carpeta, puede abrir Findaro.", "Afterwards, double-clicking a folder opens Findaro.")
                    ),
                    .init(
                        icon: "xmark.circle.fill",
                        tint: .secondary,
                        text: L10n.s("Apple no deja borrar Finder. El ▼ de Descargas en el Dock sigue siendo Finder.", "Apple does not allow deleting Finder. The Dock folder stack remains Finder.")
                    ),
                    .init(
                        icon: "dock.rectangle",
                        tint: OrdenTheme.accent,
                        text: L10n.s("Truco: arrastra una carpeta al icono de Findaro en el Dock.", "Tip: drag any folder onto the Findaro Dock icon.")
                    )
                ])
            }
            .padding(20)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: L10n.s("Atajo ⌃⌥O", "Shortcut ⌃⌥O"),
                cancelTitle: L10n.s("Cerrar", "Close"),
                actionTitle: L10n.s("Ir a Descargas", "Go to Downloads"),
                onCancel: { browser.showFolderHandlerSetupDialog = false },
                onAction: {
                    browser.navigateToDownloads()
                    browser.showFolderHandlerSetupDialog = false
                }
            )
        }
    }

    private var title: String {
        switch result {
        case .alreadyDefault: return L10n.s("Findaro ya abre carpetas", "Findaro already opens folders")
        case .readyForOpenWith: return L10n.s("Un paso más (límite de Apple)", "One more step (Apple restriction)")
        case .appMissing: return L10n.s("No encuentro Findaro.app", "Findaro.app not found")
        }
    }

    private var subtitle: String {
        switch result {
        case .alreadyDefault:
            return L10n.s("macOS ya te tiene como app de carpetas.", "macOS is already using Findaro for folders.")
        case .readyForOpenWith:
            return L10n.s("Registré Findaro. macOS no deja cambiar el default solo con un botón.", "Findaro is registered. macOS requires a manual click to confirm default app.")
        case .appMissing:
            return L10n.s("Instala Findaro en Aplicaciones y vuelve a intentar.", "Install Findaro into Applications and try again.")
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result == .appMissing ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(result == .appMissing ? .orange : .green)
            VStack(alignment: .leading, spacing: 4) {
                Text(statusHeadline)
                    .font(.headline)
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (result == .appMissing ? Color.orange : Color.green).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var statusHeadline: String {
        switch result {
        case .alreadyDefault: return L10n.s("Listo", "Ready")
        case .readyForOpenWith: return L10n.s("Findaro ya aparece en «Abrir con»", "Findaro now appears in «Open With»")
        case .appMissing: return L10n.s("Falta el .app", "Missing .app")
        }
    }

    private var statusDetail: String {
        switch result {
        case .alreadyDefault:
            return L10n.s("No tienes que hacer nada más.", "Nothing else needed.")
        case .readyForOpenWith(let path):
            return L10n.s("App: \(OrdenPathDisplay.short(path)). Elige «Siempre» una vez y listo.", "App: \(OrdenPathDisplay.short(path)). Choose «Always» once and you're set.")
        case .appMissing:
            return L10n.s("Corre el instalador o copia Findaro a /Aplicaciones.", "Run the installer or copy Findaro to /Applications.")
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(OrdenTheme.accent, in: Circle())
            Text(text)
                .font(.body)
        }
    }
}
