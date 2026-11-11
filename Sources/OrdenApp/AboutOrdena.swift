import AppKit
import OrdenCore

/// Findaro about panel; internal type name retained for compatibility.
@MainActor
enum AboutOrdena {
    static func show() {
        Task { @MainActor in
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            let status = await AppUpdateChecker.shared.aboutStatus(current: version)

            let alert = NSAlert()
            alert.messageText = "FINDARO"
            alert.informativeText = L10n.s(
                """
                Versión \(version)
                Tus archivos, bajo control.
                Encuentra. Organiza. Avanza.
                \(status.line)
                """,
                """
                Version \(version)
                Your files, under control.
                Find. Organize. Advance.
                \(status.line)
                """
            )
            alert.alertStyle = .informational
            if let icon = NSApp.applicationIconImage {
                alert.icon = icon
            }

            switch status {
            case .upToDate:
                alert.addButton(withTitle: L10n.s("Listo", "OK"))
                _ = FindaroAlert.runModal(alert)
            case .updateAvailable(let latest):
                alert.addButton(withTitle: L10n.s("Instalar \(latest)", "Install \(latest)"))
                alert.addButton(withTitle: L10n.s("Después", "Later"))
                if FindaroAlert.runModal(alert) == .alertFirstButtonReturn {
                    await AppUpdateChecker.shared.check(interactive: true)
                }
            case .unreachable:
                alert.addButton(withTitle: L10n.s("Reintentar", "Retry"))
                alert.addButton(withTitle: L10n.s("Cerrar", "Close"))
                if FindaroAlert.runModal(alert) == .alertFirstButtonReturn {
                    await AppUpdateChecker.shared.check(interactive: true)
                }
            }
        }
    }
}
