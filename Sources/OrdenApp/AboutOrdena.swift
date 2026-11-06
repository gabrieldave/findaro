import AppKit

/// Acerca de Ordena: versión + estado de actualización + botón para buscar/instalar.
@MainActor
enum AboutOrdena {
    static func show() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let alert = NSAlert()
        alert.messageText = "Ordena"
        alert.informativeText = "Versión \(version) (\(build))\nComprobando actualizaciones…"
        alert.alertStyle = .informational
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }

        // Consulta rápida antes de mostrar el diálogo definitivo.
        Task { @MainActor in
            let status = await AppUpdateChecker.shared.aboutStatus(current: version)
            alert.informativeText = """
            Versión \(version) (\(build))
            \(status.line)
            """
            alert.buttons.removeAll()
            switch status {
            case .upToDate:
                alert.addButton(withTitle: "Listo")
                _ = alert.runModal()
            case .updateAvailable(let latest):
                alert.addButton(withTitle: "Instalar \(latest)")
                alert.addButton(withTitle: "Después")
                if alert.runModal() == .alertFirstButtonReturn {
                    await AppUpdateChecker.shared.check(interactive: true)
                }
            case .unreachable(let detail):
                alert.addButton(withTitle: "Reintentar")
                alert.addButton(withTitle: "Cerrar")
                if alert.runModal() == .alertFirstButtonReturn {
                    await AppUpdateChecker.shared.check(interactive: true)
                } else {
                    _ = detail
                }
            }
        }
    }
}
