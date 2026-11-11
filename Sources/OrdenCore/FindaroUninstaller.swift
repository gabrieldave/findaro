import Foundation
import AppKit

/// Desinstalación completa de FINDARO (asiento, llavero, preferencias, Finder, .app).
@MainActor
public enum FindaroUninstaller {
    /// Diálogo de confirmación → limpia datos → mueve la app a la Papelera → cierra.
    public static func confirmAndUninstall() {
        let alert = NSAlert()
        alert.messageText = L10n.s("¿Desinstalar Findaro?", "Uninstall Findaro?")
        alert.informativeText = L10n.s(
            """
            Esto hará lo siguiente:
            • Liberará el asiento de licencia de esta Mac (si hay licencia activa)
            • Borrará datos locales de licencia y prueba del Llavero
            • Restaurar Finder como explorador por defecto (si aplica)
            • Mover Findaro.app a la Papelera

            Tus archivos personales no se tocan. La clave de licencia (correo de compra) sigue siendo válida para otra Mac.
            """,
            """
            This will:
            • Free this Mac’s license seat (if a license is active)
            • Remove local license and trial data from the Keychain
            • Restore Finder as the default file viewer (if applicable)
            • Move Findaro.app to the Trash

            Your personal files are not touched. Your license key (purchase email) remains valid on another Mac.
            """
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.s("Desinstalar", "Uninstall"))
        alert.addButton(withTitle: L10n.s("Cancelar", "Cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            await performUninstall()
        }
    }

    public static func performUninstall() async {
        // 1. Liberar asiento en servidor + limpiar licencia local
        try? await LicenseStore.shared.deactivate()
        // 2. Limpiar trial y restos de llavero/defaults que deactivate no toca
        LicenseStore.shared.wipeLocalDataForUninstall()
        // 3. Restaurar Finder si era el visor por defecto
        _ = DefaultFileViewerManager.disable()
        // 4. Preferencias del bundle
        removePreferencesDomain()
        // 5. Mover .app a la Papelera
        trashInstalledApp()
        // 6. Salir
        NSApp.terminate(nil)
    }

    private static func removePreferencesDomain() {
        let domain = DefaultFileViewerManager.bundleID
        if let defs = UserDefaults(suiteName: domain) {
            defs.removePersistentDomain(forName: domain)
            defs.synchronize()
        }
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()

        let prefsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(domain).plist")
        try? FileManager.default.removeItem(at: prefsURL)

        let supportURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Findaro")
        try? FileManager.default.removeItem(at: supportURL)
        let legacySupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ordena")
        try? FileManager.default.removeItem(at: legacySupport)
    }

    private static func trashInstalledApp() {
        let candidates: [URL] = [
            Bundle.main.bundleURL,
            URL(fileURLWithPath: "/Applications/Findaro.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Findaro.app"),
            URL(fileURLWithPath: "/Applications/Ordena.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Ordena.app")
        ]
        var seen = Set<String>()
        for url in candidates {
            let path = url.standardizedFileURL.path
            guard path.hasSuffix(".app"), !seen.contains(path) else { continue }
            seen.insert(path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }
}
