import SwiftUI
import OrdenCore

/// Explica el límite de macOS y los pasos reales para abrir carpetas con Ordena.
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

                OrdenDialogSection(title: "Cómo dejarlo fijo") {
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "Clic derecho en cualquier carpeta")
                        step(2, "Abrir con → Ordena")
                        step(3, "Vuelve a clic derecho → Abrir con → Siempre")
                    }
                }

                OrdenDialogHintBox(rows: [
                    .init(
                        icon: "checkmark.circle.fill",
                        tint: .green,
                        text: "Después, al hacer doble clic en una carpeta, puede abrir Ordena."
                    ),
                    .init(
                        icon: "xmark.circle.fill",
                        tint: .secondary,
                        text: "Apple no deja borrar Finder. El ▼ de Descargas en el Dock sigue siendo Finder."
                    ),
                    .init(
                        icon: "dock.rectangle",
                        tint: OrdenTheme.accent,
                        text: "Truco: arrastra una carpeta al icono de Ordena en el Dock."
                    )
                ])
            }
            .padding(20)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: "Atajo ⌃⌥O",
                cancelTitle: "Cerrar",
                actionTitle: "Mostrar Descargas",
                onCancel: { browser.showFolderHandlerSetupDialog = false },
                onAction: {
                    OpenFolderBridge.revealInFinderForOpenWithDemo()
                    browser.showFolderHandlerSetupDialog = false
                }
            )
        }
    }

    private var title: String {
        switch result {
        case .alreadyDefault: return "Ordena ya abre carpetas"
        case .readyForOpenWith: return "Un paso más (límite de Apple)"
        case .appMissing: return "No encuentro Ordena.app"
        }
    }

    private var subtitle: String {
        switch result {
        case .alreadyDefault:
            return "macOS ya te tiene como app de carpetas."
        case .readyForOpenWith:
            return "Registré Ordena. macOS no deja cambiar el default solo con un botón."
        case .appMissing:
            return "Instala Ordena en Aplicaciones y vuelve a intentar."
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
        case .alreadyDefault: return "Listo"
        case .readyForOpenWith: return "Ordena ya aparece en «Abrir con»"
        case .appMissing: return "Falta el .app"
        }
    }

    private var statusDetail: String {
        switch result {
        case .alreadyDefault:
            return "No tienes que hacer nada más."
        case .readyForOpenWith(let path):
            return "App: \(OrdenPathDisplay.short(path)). Elige «Siempre» una vez y listo."
        case .appMissing:
            return "Corre el instalador o copia Ordena a /Aplicaciones."
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
